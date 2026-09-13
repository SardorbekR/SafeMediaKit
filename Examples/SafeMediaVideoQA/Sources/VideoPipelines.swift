import AVFoundation
import CoreImage
import UIKit
import VideoToolbox
import os

enum QAError: Error { case cameraUnavailable, pipelineSetup, videoUnavailable }

/// Configuration completes before publication. Thereafter only the serial queue
/// starts/stops the session; callers only attach the input and preview layer as
/// supported by AVFoundation. No audio input or recording output is installed.
/// Revisit this narrow unchecked conformance when AVFoundation exposes an
/// isolation-aware capture-session lifecycle API.
final class CapturePipeline: @unchecked Sendable {
    let session = AVCaptureSession()
    let input: AVCaptureDeviceInput
    private let queue = DispatchQueue(label: "SafeMediaVideoQA.capture")

    init() throws {
        guard
            let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video, position: .back)
        else {
            throw QAError.cameraUnavailable
        }
        input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .medium
        guard session.canAddInput(input) else { throw QAError.pipelineSetup }
        session.addInput(input)
    }

    // Enqueue on the controller's actor before suspending. Otherwise the hop
    // to a nonisolated async executor could let Stop enqueue before Start.
    @MainActor func start() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.session.startRunning()
                continuation.resume()
            }
        }
    }

    @MainActor func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.session.stopRunning()
                continuation.resume()
            }
        }
    }
}

/// Deliberately small local-file stand-in for a received compressed stream.
/// Compressed samples go through the exact VT session attached to Apple's
/// analyzer. No AVPlayer or separately decoded bypass path is used.
@MainActor
final class DecodePipeline {
    let session: VTDecompressionSession
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private var playback: Task<Void, Never>?
    private var presentations: [UUID: Task<Void, Never>] = [:]
    private var presentationGeneration = 0
    private var lastPresentedOffset = -Double.infinity

    init(url: URL) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first,
            let format = try await track.load(.formatDescriptions).first
        else {
            throw QAError.videoUnavailable
        }
        try Task.checkCancellation()
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { throw QAError.pipelineSetup }
        reader.add(output)
        var decoder: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault, formatDescription: format,
            decoderSpecification: nil,
            imageBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey:
                    kCVPixelFormatType_32BGRA
            ] as CFDictionary,
            outputCallback: nil, decompressionSessionOut: &decoder
        )
        guard status == noErr, let decoder else { throw QAError.pipelineSetup }
        session = decoder
    }

    func start(
        frame: @escaping @MainActor @Sendable (CGImage) -> Void,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        guard reader.startReading() else {
            completion()
            return
        }
        playback = Task { @MainActor [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()
            var origin: ContinuousClock.Instant?
            var firstTimestamp: Double?
            let context = CIContext()
            while !Task.isCancelled, let sample = output.copyNextSampleBuffer() {
                // Compressed readers also emit track-boundary markers. They
                // have no media samples and are not valid VT decode input.
                guard sample.numSamples > 0 else { continue }
                let timestamp = sample.presentationTimeStamp.seconds
                guard timestamp.isFinite else {
                    completion()
                    return
                }
                if firstTimestamp == nil { firstTimestamp = timestamp }
                let offset = max(0, timestamp - (firstTimestamp ?? timestamp))
                // Compressed samples arrive in decode order. Pace input by DTS
                // but present by PTS so B-frames do not jump backward on screen.
                let decodeTimestamp = sample.decodeTimeStamp.seconds
                let decodeOffset = max(
                    0,
                    (decodeTimestamp.isFinite ? decodeTimestamp : timestamp)
                        - (firstTimestamp ?? timestamp))
                let duration = sample.duration.seconds
                let endOffset = offset + (duration.isFinite && duration > 0 ? duration : 0)
                guard offset.isFinite, decodeOffset.isFinite, endOffset.isFinite,
                    max(decodeOffset, endOffset) < Double(Int64.max) / 2
                else {
                    completion()
                    return
                }
                if let origin {
                    do {
                        try await clock.sleep(until: origin.advanced(by: .seconds(decodeOffset)))
                    } catch { return }
                }
                guard !Task.isCancelled else { return }
                let currentPresentation = presentationGeneration
                let outputFrames = OSAllocatedUnfairLock(
                    initialState: (images: [CGImage](), failed: false))
                let status = VTDecompressionSessionDecodeFrame(
                    session, sampleBuffer: sample, flags: [], infoFlagsOut: nil
                ) { status, _, buffer, _, _ in
                    guard status == noErr else {
                        outputFrames.withLock { $0.failed = true }
                        return
                    }
                    guard let buffer else { return }
                    let image = CIImage(cvPixelBuffer: buffer)
                    guard let rendered = context.createCGImage(image, from: image.extent) else {
                        outputFrames.withLock { $0.failed = true }
                        return
                    }
                    outputFrames.withLock { $0.images.append(rendered) }
                }
                // With flags=[] VideoToolbox completes every output callback
                // before returning (though not necessarily on this actor).
                // Register presentation work here, not in fire-and-forget hops
                // from those callbacks that EOF could overtake.
                let result = outputFrames.withLock { $0 }
                guard status == noErr, !result.failed else {
                    completion()
                    return
                }
                // Start the media clock after the first decode/render has
                // warmed up, so initialization cost doesn't discard preroll.
                let presentationOrigin = origin ?? clock.now
                origin = presentationOrigin
                for image in result.images {
                    let id = UUID()
                    presentations[id] = Task { @MainActor [weak self] in
                        defer { self?.presentations[id] = nil }
                        do {
                            try await clock.sleep(
                                until: presentationOrigin.advanced(by: .seconds(offset)))
                        } catch { return }
                        guard let self, !Task.isCancelled,
                            self.presentationGeneration == currentPresentation
                        else { return }
                        // If decoding or scheduling falls behind, drop stale
                        // output rather than moving backward through the clip.
                        guard offset >= self.lastPresentedOffset else { return }
                        self.lastPresentedOffset = offset
                        frame(image)
                        // Keep the final image visible for its sample duration;
                        // EOF must not clear it in the same run-loop pass.
                        try? await clock.sleep(
                            until: presentationOrigin.advanced(by: .seconds(endOffset)))
                    }
                }
            }
            guard !Task.isCancelled else { return }
            let pending = Array(presentations.values)
            for presentation in pending { await presentation.value }
            guard !Task.isCancelled else { return }
            completion()
        }
    }

    func stop() {
        discardPendingFrames()
        playback?.cancel()
        playback = nil
        reader.cancelReading()
        VTDecompressionSessionInvalidate(session)
    }

    func discardPendingFrames() {
        presentationGeneration += 1
        for presentation in presentations.values { presentation.cancel() }
        presentations.removeAll()
    }
}
