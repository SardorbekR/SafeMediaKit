#if canImport(SensitiveContentAnalysis) && os(iOS) && !targetEnvironment(macCatalyst)
import AVFoundation
import SensitiveContentAnalysis
import VideoToolbox

/// Analyzes one attached live video stream with Apple's Sensitive Content
/// Analysis framework.
///
/// Create one instance per stream. Use a unique, call-scoped participant
/// identifier and reuse it for that participant's other streams in the call.
///
/// While analysis remains attached, Apple's capture-input and
/// decompression-session integrations censor video when sensitive content is
/// detected and keep it censored until ``continueStream()`` is called. Ending
/// analysis can remove that protection, so conceal or stop the host pipeline
/// before teardown. Audio muting remains the host app's responsibility and is
/// reported through ``SafeMediaGuidance``.
@available(iOS 26.0, *)
@MainActor
public final class AppleSensitiveContentStreamAnalyzer: SafeMediaStreamAnalyzing {
    private enum Source {
        case captureDeviceInput(AVCaptureDeviceInput)
        case decompressionSession(VTDecompressionSession)

        var direction: SCVideoStreamAnalyzer.StreamDirection {
            switch self {
            case .captureDeviceInput:
                .outgoing
            case .decompressionSession:
                .incoming
            }
        }
    }

    private let participantID: String
    private let source: Source

    private var generation: UInt = 0
    private var analyzer: SCVideoStreamAnalyzer?
    private var forwardingTask: Task<Void, Never>?
    private var eventContinuation:
        AsyncThrowingStream<SafeMediaVerdict, any Error>.Continuation?
    private var hasBegunAnalysis = false

    /// Creates an analyzer for a capture-device stream.
    ///
    /// - Parameters:
    ///   - participantID: A unique, call-scoped identifier for the participant
    ///     who owns the stream. Reuse it for that participant's other streams.
    ///   - captureDeviceInput: The capture input Apple should monitor.
    public init(
        participantID: String,
        captureDeviceInput: AVCaptureDeviceInput
    ) {
        self.participantID = participantID
        self.source = .captureDeviceInput(captureDeviceInput)
    }

    /// Creates an analyzer for a decoded incoming stream.
    ///
    /// - Parameters:
    ///   - participantID: A unique, call-scoped identifier for the participant
    ///     who owns the stream. Reuse it for that participant's other streams.
    ///   - decompressionSession: The VideoToolbox decompression session Apple
    ///     should monitor.
    public init(
        participantID: String,
        decompressionSession: VTDecompressionSession
    ) {
        self.participantID = participantID
        self.source = .decompressionSession(decompressionSession)
    }

    /// Reports whether the device's sensitive-content analysis policy is
    /// enabled and the configured stream direction is supported.
    public func availability() async -> SafeMediaAvailability {
        guard SCSensitivityAnalyzer().analysisPolicy != .disabled else {
            return .unavailable(.analysisPolicyDisabled)
        }

        do {
            _ = try SCVideoStreamAnalyzer(
                participantUUID: participantID,
                streamDirection: source.direction
            )
            return .available
        } catch {
            return SCSensitivityAnalyzer().analysisPolicy == .disabled
                ? .unavailable(.analysisPolicyDisabled)
                : .unavailable(.unsupportedPlatform)
        }
    }

    /// Attaches the configured Apple media pipeline and returns mapped verdict
    /// events.
    public func startAnalysis() async throws
        -> AsyncThrowingStream<SafeMediaVerdict, any Error> {
        invalidateCurrentAnalysis()
        let currentGeneration = generation

        let analyzer = try SCVideoStreamAnalyzer(
            participantUUID: participantID,
            streamDirection: source.direction
        )
        let (events, continuation) = AsyncThrowingStream<
            SafeMediaVerdict,
            any Error
        >.makeStream(bufferingPolicy: .unbounded)

        self.analyzer = analyzer
        self.eventContinuation = continuation

        continuation.onTermination = { @Sendable [weak self] termination in
            guard case .cancelled = termination else { return }

            Task { @MainActor [weak self] in
                self?.endAnalysis(ifCurrent: currentGeneration)
            }
        }

        await withCheckedContinuation { ready in
            forwardingTask = Task { @MainActor [analyzer, continuation] in
                ready.resume()

                do {
                    for try await analysis in analyzer.analysisChanges {
                        guard !Task.isCancelled else { break }
                        switch continuation.yield(
                            SCAResultMapper.mapStream(analysis)
                        ) {
                        case .enqueued:
                            break
                        case .terminated, .dropped:
                            return
                        @unknown default:
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }

        guard isCurrent(currentGeneration, analyzer: analyzer),
              !Task.isCancelled else {
            continuation.finish()
            endAnalysis(ifCurrent: currentGeneration)
            throw CancellationError()
        }

        do {
            switch source {
            case .captureDeviceInput(let input):
                try analyzer.beginAnalysis(of: input)
            case .decompressionSession(let session):
                try analyzer.beginAnalysis(of: session)
            }
        } catch {
            continuation.finish(throwing: error)
            endAnalysis(ifCurrent: currentGeneration)
            throw error
        }

        hasBegunAnalysis = true

        guard isCurrent(currentGeneration, analyzer: analyzer),
              !Task.isCancelled else {
            continuation.finish()
            endAnalysis(ifCurrent: currentGeneration)
            throw CancellationError()
        }

        return events
    }

    /// Resumes Apple's analysis and stops its capture or decompression
    /// censorship.
    public func continueStream() {
        guard hasBegunAnalysis else { return }
        analyzer?.continueStream()
    }

    /// Stops the current Apple analysis and its verdict-forwarding task.
    public func endAnalysis() {
        invalidateCurrentAnalysis()
    }

    isolated deinit {
        eventContinuation?.finish()
        forwardingTask?.cancel()
        if hasBegunAnalysis {
            analyzer?.endAnalysis()
        }
    }

    private func isCurrent(
        _ generation: UInt,
        analyzer: SCVideoStreamAnalyzer
    ) -> Bool {
        self.generation == generation && self.analyzer === analyzer
    }

    private func endAnalysis(ifCurrent generation: UInt) {
        guard self.generation == generation else { return }
        invalidateCurrentAnalysis()
    }

    private func invalidateCurrentAnalysis() {
        generation &+= 1
        stopCurrentAnalysis()
    }

    private func stopCurrentAnalysis() {
        eventContinuation?.finish()
        eventContinuation = nil

        forwardingTask?.cancel()
        forwardingTask = nil

        if hasBegunAnalysis {
            hasBegunAnalysis = false
            analyzer?.endAnalysis()
        }
        analyzer = nil
    }
}
#endif
