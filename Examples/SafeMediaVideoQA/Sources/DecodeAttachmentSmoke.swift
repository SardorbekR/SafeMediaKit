import Foundation
import SafeMediaKit

/// Exercises attachment only. No reader starts, no frame is decoded/submitted,
/// no verdict sequence is iterated, and no camera or microphone is constructed.
@MainActor
enum DecodeAttachmentSmoke {
    private enum Failure: Error {
        case missingFixture, unavailable, cancellationMissed
    }

    static func run() async -> Bool {
        var stage = "fixture setup"
        do {
            guard let url = Bundle.main.url(forResource: "solid-gray", withExtension: "mp4") else {
                throw Failure.missingFixture
            }
            let participantID = UUID().uuidString
            for cycle in 1...10 {
                stage = "attachment cycle \(cycle)"
                let decoder = try await DecodePipeline(url: url)
                let analyzer = AppleSensitiveContentStreamAnalyzer(
                    participantID: participantID, decompressionSession: decoder.session)
                defer {
                    analyzer.endAnalysis()
                    decoder.stop()
                }
                guard await analyzer.availability() == .available else {
                    throw Failure.unavailable
                }
                let events = try await analyzer.startAnalysis()
                withExtendedLifetime(events) { analyzer.endAnalysis() }
            }
            print("QA decode lifecycle: PASS 10 availability/start/end cycles, participant ID reused")

            stage = "startup cancellation"
            let decoder = try await DecodePipeline(url: url)
            let analyzer = AppleSensitiveContentStreamAnalyzer(
                participantID: participantID, decompressionSession: decoder.session)
            defer {
                analyzer.endAnalysis()
                decoder.stop()
            }
            let startup = Task { @MainActor in try await analyzer.startAnalysis() }
            await Task.yield()
            startup.cancel()
            do {
                let events = try await startup.value
                withExtendedLifetime(events) { analyzer.endAnalysis() }
                throw Failure.cancellationMissed
            } catch is CancellationError {
                print("QA decode lifecycle: PASS cancelled startup returned CancellationError")
            }

            stage = "restart after cancellation"
            guard await analyzer.availability() == .available else {
                throw Failure.unavailable
            }
            let events = try await analyzer.startAnalysis()
            withExtendedLifetime(events) { analyzer.endAnalysis() }
            print("QA decode lifecycle: PASS restart after cancellation; no frames submitted")
            return true
        } catch Failure.cancellationMissed {
            print("QA decode lifecycle: INCONCLUSIVE cancellation scheduling; startup completed before cancellation was observed")
            return false
        } catch {
            // Domain/code identify setup/API failures without serializing media
            // results, arbitrary error descriptions, file paths, or user data.
            let error = error as NSError
            print("QA decode lifecycle: FAIL \(stage); domain=\(error.domain), code=\(error.code)")
            return false
        }
    }
}
