import SafeMediaKit
import SafeMediaKitTesting
import XCTest

@MainActor
final class MockStreamAnalyzerTests: XCTestCase {
    func testScriptEmitsEventsInOrder() async throws {
        let analyzer = MockStreamAnalyzer(
            events: [.success(.mockSafe), .success(.mockSensitiveVideo)]
        )
        let stream = try await analyzer.startAnalysis()
        let sensitiveReceived = expectation(description: "sensitive verdict received")
        let consumerFinished = expectation(description: "consumer finished")
        let consumer = Task { @MainActor in
            defer { consumerFinished.fulfill() }
            var verdicts: [SafeMediaVerdict] = []
            for try await verdict in stream {
                verdicts.append(verdict)
                if verdict.sensitivity == .sensitive {
                    sensitiveReceived.fulfill()
                }
            }
            return verdicts
        }

        await fulfillment(of: [sensitiveReceived], timeout: 5)
        analyzer.continueStream()
        analyzer.endAnalysis()
        guard await waitForTaskCompletion(
            of: consumer,
            signaledBy: consumerFinished
        ) else { return }
        let verdicts = try await consumer.value

        XCTAssertEqual(verdicts, [.mockSafe, .mockSensitiveVideo])
        XCTAssertEqual(analyzer.startAnalysisCallCount, 1)
    }

    func testSensitiveScriptPausesUntilContinueStream() async throws {
        let analyzer = MockStreamAnalyzer(
            events: [.success(.mockSensitiveVideo), .success(.mockSafe)]
        )
        let stream = try await analyzer.startAnalysis()
        let sensitiveReceived = expectation(description: "sensitive verdict received")
        let safeReceived = expectation(description: "safe verdict received")
        let consumerFinished = expectation(description: "consumer finished")
        var verdicts: [SafeMediaVerdict] = []
        let consumer = Task { @MainActor in
            defer { consumerFinished.fulfill() }
            for try await verdict in stream {
                verdicts.append(verdict)
                if verdict.sensitivity == .sensitive {
                    sensitiveReceived.fulfill()
                } else {
                    safeReceived.fulfill()
                }
            }
        }

        await fulfillment(of: [sensitiveReceived], timeout: 5)
        XCTAssertEqual(verdicts, [.mockSensitiveVideo])

        analyzer.continueStream()
        await fulfillment(of: [safeReceived], timeout: 5)
        analyzer.endAnalysis()
        guard await waitForTaskCompletion(
            of: consumer,
            signaledBy: consumerFinished
        ) else { return }
        try await consumer.value

        XCTAssertEqual(verdicts, [.mockSensitiveVideo, .mockSafe])
        XCTAssertEqual(analyzer.continueStreamCallCount, 1)
    }

    func testScriptStopsAtFirstFailure() async throws {
        let analyzer = MockStreamAnalyzer(
            events: [
                .success(.mockSafe),
                .failure(SafeMediaError.analysisFailed("forced")),
                .success(.mockSensitiveVideo)
            ]
        )
        let stream = try await analyzer.startAnalysis()
        let consumerFinished = expectation(description: "consumer finished")
        let consumer = Task { @MainActor in
            defer { consumerFinished.fulfill() }
            var verdicts: [SafeMediaVerdict] = []

            do {
                for try await verdict in stream {
                    verdicts.append(verdict)
                }
                XCTFail("Expected the scripted failure")
            } catch {
                XCTAssertEqual(
                    error as? SafeMediaError,
                    .analysisFailed("forced")
                )
            }

            return verdicts
        }

        guard await waitForTaskCompletion(
            of: consumer,
            signaledBy: consumerFinished
        ) else { return }
        let verdicts = await consumer.value
        XCTAssertEqual(verdicts, [.mockSafe])
    }

    func testFactoryProducesFreshStreamForEachStart() async throws {
        var factoryCallCount = 0
        let analyzer = MockStreamAnalyzer {
            factoryCallCount += 1
            return MockStreamAnalyzer.EventStream { continuation in
                continuation.yield(.mockSafe)
                continuation.finish()
            }
        }

        for _ in 0..<2 {
            let consumerFinished = expectation(description: "consumer finished")
            let consumer = Task { @MainActor in
                defer { consumerFinished.fulfill() }
                let stream = try await analyzer.startAnalysis()
                var iterator = stream.makeAsyncIterator()
                return (
                    try await iterator.next(),
                    try await iterator.next()
                )
            }
            guard await waitForTaskCompletion(
                of: consumer,
                signaledBy: consumerFinished
            ) else { return }
            let (first, second) = try await consumer.value
            XCTAssertEqual(first, .mockSafe)
            XCTAssertNil(second)
        }

        XCTAssertEqual(factoryCallCount, 2)
        XCTAssertEqual(analyzer.startAnalysisCallCount, 2)
    }

    func testRecordsAvailabilityResumeAndEndCalls() async {
        let analyzer = MockStreamAnalyzer(
            events: [],
            availability: .unavailable(.analysisPolicyDisabled)
        )

        let availability = await analyzer.availability()
        XCTAssertEqual(availability, .unavailable(.analysisPolicyDisabled))
        analyzer.continueStream()
        analyzer.endAnalysis()

        XCTAssertEqual(analyzer.availabilityCallCount, 1)
        XCTAssertEqual(analyzer.continueStreamCallCount, 1)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
    }

    func testEndAnalysisStopsTheActiveFactoryStream() async throws {
        let (source, sourceContinuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let sourceTerminated = expectation(description: "source terminated")
        sourceContinuation.onTermination = { @Sendable _ in
            sourceTerminated.fulfill()
        }
        let analyzer = MockStreamAnalyzer { source }
        let stream = try await analyzer.startAnalysis()
        let consumerFinished = expectation(description: "consumer finished")
        let consumer = Task { @MainActor in
            defer { consumerFinished.fulfill() }
            var verdicts: [SafeMediaVerdict] = []
            do {
                for try await verdict in stream {
                    verdicts.append(verdict)
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
            return verdicts
        }

        analyzer.endAnalysis()
        guard await waitForTaskCompletion(
            of: consumer,
            signaledBy: consumerFinished
        ) else { return }
        let verdicts = await consumer.value
        await fulfillment(of: [sourceTerminated], timeout: 5)

        XCTAssertTrue(verdicts.isEmpty)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
        if case .terminated = sourceContinuation.yield(.mockSafe) {
            // Expected after teardown.
        } else {
            XCTFail("Expected teardown to invalidate the source stream")
        }
    }

    func testEndAnalysisTerminatesSourceReturnedBySuspendedFactory() async {
        let factoryEntered = expectation(description: "factory entered")
        let startFinished = expectation(description: "start finished")
        let gate = MockFactoryGate {
            factoryEntered.fulfill()
        }
        let (source, sourceContinuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let sourceTerminated = expectation(description: "stale source terminated")
        sourceContinuation.onTermination = { @Sendable _ in
            sourceTerminated.fulfill()
        }
        let analyzer = MockStreamAnalyzer {
            await gate.wait()
            return source
        }
        let startTask = Task { @MainActor in
            defer { startFinished.fulfill() }
            return try await analyzer.startAnalysis()
        }

        await fulfillment(of: [factoryEntered], timeout: 5)
        analyzer.endAnalysis()
        gate.open()
        guard await waitForTaskCompletion(
            of: startTask,
            signaledBy: startFinished
        ) else { return }

        do {
            _ = try await startTask.value
            XCTFail("Expected the invalidated start to be cancelled")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await fulfillment(of: [sourceTerminated], timeout: 5)
        if case .terminated = sourceContinuation.yield(.mockSafe) {
            // Expected after stale-source teardown.
        } else {
            XCTFail("Expected the stale source to reject new verdicts")
        }
    }

    func testConsumerCancellationTerminatesTheFactorySource() async throws {
        let (source, sourceContinuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let sourceTerminated = expectation(description: "source terminated")
        sourceContinuation.onTermination = { @Sendable _ in
            sourceTerminated.fulfill()
        }
        let analyzer = MockStreamAnalyzer { source }
        let stream = try await analyzer.startAnalysis()
        let firstReceived = expectation(description: "first verdict received")
        let consumerFinished = expectation(description: "consumer finished")
        let consumer = Task { @MainActor in
            defer { consumerFinished.fulfill() }
            do {
                for try await _ in stream {
                    firstReceived.fulfill()
                    withUnsafeCurrentTask { task in
                        task?.cancel()
                    }
                }
            } catch is CancellationError {
                // AsyncThrowingStream may surface cancellation as an error.
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        sourceContinuation.yield(.mockSafe)
        await fulfillment(of: [firstReceived], timeout: 5)
        guard await waitForTaskCompletion(
            of: consumer,
            signaledBy: consumerFinished
        ) else { return }
        await consumer.value
        await fulfillment(of: [sourceTerminated], timeout: 5)

        if case .terminated = sourceContinuation.yield(.mockSensitiveVideo) {
            // Expected after consumer cancellation.
        } else {
            XCTFail("Expected cancellation to invalidate the source stream")
        }
    }

    func testPausedScriptDoesNotRetainTheAnalyzer() async throws {
        var analyzer: MockStreamAnalyzer? = MockStreamAnalyzer(
            events: [.success(.mockSensitiveVideo)]
        )
        let analyzerReference = WeakMockStreamAnalyzerReference(analyzer)
        let stream = try await analyzer?.startAnalysis()
        let sensitiveReceived = expectation(description: "sensitive received")
        let consumerFinished = expectation(description: "consumer finished")
        let consumer = Task { @MainActor in
            defer { consumerFinished.fulfill() }
            do {
                if let stream {
                    for try await verdict in stream {
                        if verdict.sensitivity == .sensitive {
                            sensitiveReceived.fulfill()
                        }
                    }
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        await fulfillment(of: [sensitiveReceived], timeout: 5)
        analyzer = nil

        XCTAssertNil(analyzerReference.value)
        guard await waitForTaskCompletion(
            of: consumer,
            signaledBy: consumerFinished
        ) else { return }
        await consumer.value
    }

    private func waitForTaskCompletion<Success: Sendable, Failure: Error>(
        of task: Task<Success, Failure>,
        signaledBy expectation: XCTestExpectation,
        timeout: TimeInterval = 5
    ) async -> Bool {
        let result = await XCTWaiter.fulfillment(
            of: [expectation],
            timeout: timeout
        )
        guard result == .completed else {
            task.cancel()
            XCTFail("Timed out waiting for test task completion")
            return false
        }
        return true
    }
}

@MainActor
private final class WeakMockStreamAnalyzerReference {
    weak var value: MockStreamAnalyzer?

    init(_ value: MockStreamAnalyzer?) {
        self.value = value
    }
}

@MainActor
private final class MockFactoryGate {
    private let onEntry: @MainActor () -> Void
    private var isOpen = false
    private var waitContinuation: CheckedContinuation<Void, Never>?

    init(onEntry: @escaping @MainActor () -> Void) {
        self.onEntry = onEntry
    }

    func wait() async {
        onEntry()

        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waitContinuation = continuation
        }
    }

    func open() {
        isOpen = true
        waitContinuation?.resume()
        waitContinuation = nil
    }
}
