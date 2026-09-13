import CoreGraphics
import XCTest

/// Exercises only the synthetic gray fixture, without an SCA analyzer or sensors.
@MainActor
final class DecodePipelineTests: XCTestCase {
    // Cold CI simulators can spend several seconds initializing VideoToolbox
    // and Core Image. This bounds callback waits, not playback performance;
    // frame order/count and presentation duration remain independently asserted.
    private let callbackTimeout: TimeInterval = 30

    func testSingleFrameIsPresentedBeforeCompletionAndHeldForItsDuration() async throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "solid-gray", withExtension: "mp4"))
        let pipeline = try await DecodePipeline(url: url)
        defer { pipeline.stop() }
        let completed = expectation(description: "Playback completed")
        var callbacks: [String] = []
        var presentedAt: ContinuousClock.Instant?
        var completedAt: ContinuousClock.Instant?
        pipeline.start { image in
            XCTAssertEqual(image.width, 64)
            XCTAssertEqual(image.height, 64)
            callbacks.append("frame")
            presentedAt = .now
        } completion: {
            callbacks.append("completion")
            completedAt = .now
            // Match the controller's real EOF behavior, which invalidates frames.
            pipeline.stop()
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: callbackTimeout)
        XCTAssertEqual(callbacks, ["frame", "completion"])
        let start = try XCTUnwrap(presentedAt)
        let end = try XCTUnwrap(completedAt)
        XCTAssertGreaterThanOrEqual(start.duration(to: end), .milliseconds(800))
    }

    func testBFramesArePresentedInDisplayOrder() async throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "gray-ramp-bframes", withExtension: "mp4"))
        let pipeline = try await DecodePipeline(url: url)
        defer { pipeline.stop() }
        let completed = expectation(description: "Playback completed")
        var brightness: [UInt8] = []
        pipeline.start { image in
            // The synthetic fixture increases uniform luminance every frame.
            var pixel = [UInt8](repeating: 0, count: 4)
            pixel.withUnsafeMutableBytes { bytes in
                let context = CGContext(
                    data: bytes.baseAddress, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            brightness.append(pixel[0])
        } completion: {
            pipeline.stop()
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: callbackTimeout)
        XCTAssertEqual(brightness.count, 10, "Presented luminance: \(brightness)")
        XCTAssertEqual(brightness, brightness.sorted())
        XCTAssertEqual(Set(brightness).count, 10)
    }

    func testStopFromFrameDeliveryCancelsPendingFramesAndCompletion() async throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "gray-ramp-bframes", withExtension: "mp4"))
        let pipeline = try await DecodePipeline(url: url)
        defer { pipeline.stop() }
        let firstFrame = expectation(description: "First frame")
        let unexpected = expectation(description: "No callbacks after Stop")
        unexpected.isInverted = true
        var frameCount = 0
        pipeline.start { _ in
            frameCount += 1
            if frameCount == 1 {
                pipeline.stop()
                firstFrame.fulfill()
            } else {
                unexpected.fulfill()
            }
        } completion: {
            unexpected.fulfill()
        }
        await fulfillment(of: [firstFrame], timeout: callbackTimeout)
        await fulfillment(of: [unexpected], timeout: 2.2)
        XCTAssertEqual(frameCount, 1)
    }
}
