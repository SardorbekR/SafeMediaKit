import SafeMediaKit

/// A configurable live-video analyzer for tests, previews, and demos.
///
/// Each call to ``startAnalysis()`` returns a fresh event stream. Use the
/// scripted initializer for ordered events or the factory initializer for a
/// manually controlled stream in cancellation and lifecycle tests.
@MainActor
public final class MockStreamAnalyzer: SafeMediaStreamAnalyzing {
    /// The concrete stream type produced by the mock.
    public typealias EventStream = AsyncThrowingStream<
        SafeMediaVerdict,
        any Error
    >

    /// The value returned by ``availability()``.
    public var availabilityResult: SafeMediaAvailability

    /// The number of availability preflights performed.
    public private(set) var availabilityCallCount = 0

    /// The number of fresh event streams requested.
    public private(set) var startAnalysisCallCount = 0

    /// The number of resume requests received.
    public private(set) var continueStreamCallCount = 0

    /// The number of analysis teardown requests received.
    public private(set) var endAnalysisCallCount = 0

    private let scriptedEvents: [Result<SafeMediaVerdict, any Error>]?
    private let makeEventStream: (@MainActor @Sendable () async throws -> EventStream)?
    private var generation: UInt = 0
    private var activeContinuation: EventStream.Continuation?
    private var forwardingTask: Task<Void, Never>?
    private var pauseGate: MockStreamPauseGate?

    /// Creates a mock that emits the supplied results in order.
    ///
    /// Successful scripts remain active until ``endAnalysis()``. A sensitive
    /// verdict pauses the script until ``continueStream()``. The first failure
    /// terminates the stream.
    public init(
        events: [Result<SafeMediaVerdict, any Error>],
        availability: SafeMediaAvailability = .available
    ) {
        self.scriptedEvents = events
        self.makeEventStream = nil
        self.availabilityResult = availability
    }

    /// Creates a mock whose factory supplies a fresh event stream for every
    /// analysis start.
    public init(
        availability: SafeMediaAvailability = .available,
        makeEventStream: @escaping @MainActor @Sendable () async throws
            -> EventStream
    ) {
        self.scriptedEvents = nil
        self.makeEventStream = makeEventStream
        self.availabilityResult = availability
    }

    /// Returns the configured availability value.
    public func availability() async -> SafeMediaAvailability {
        availabilityCallCount += 1
        return availabilityResult
    }

    /// Returns a new scripted or factory-provided event stream.
    public func startAnalysis() async throws -> EventStream {
        startAnalysisCallCount += 1
        invalidateActiveStream()
        let currentGeneration = generation

        let source: EventStream
        if let makeEventStream {
            source = try await makeEventStream()
        } else {
            let scriptedEvents = scriptedEvents ?? []
            source = EventStream(bufferingPolicy: .unbounded) { continuation in
                for event in scriptedEvents {
                    switch event {
                    case .success(let verdict):
                        continuation.yield(verdict)
                    case .failure(let error):
                        continuation.finish(throwing: error)
                        return
                    }
                }
            }
        }

        guard generation == currentGeneration, !Task.isCancelled else {
            await terminate(source)
            throw CancellationError()
        }

        let (events, continuation) = EventStream.makeStream(
            bufferingPolicy: .unbounded
        )
        let pauseGate = MockStreamPauseGate()
        self.pauseGate = pauseGate
        activeContinuation = continuation

        continuation.onTermination = { @Sendable [weak self] termination in
            guard case .cancelled = termination else { return }

            Task { @MainActor [weak self] in
                self?.invalidateActiveStream(ifCurrent: currentGeneration)
            }
        }

        forwardingTask = Task { @MainActor [
            weak self,
            source,
            continuation,
            pauseGate
        ] in
            defer {
                self?.clearActiveStream(ifCurrent: currentGeneration)
            }

            do {
                for try await verdict in source {
                    guard !Task.isCancelled else { return }
                    if verdict.sensitivity == .sensitive {
                        guard pauseGate.preparePause() else {
                            return
                        }
                    }
                    switch continuation.yield(verdict) {
                    case .terminated, .dropped:
                        return
                    case .enqueued:
                        if verdict.sensitivity == .sensitive {
                            guard await pauseGate.waitUntilContinued() else {
                                return
                            }
                        }
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

        return events
    }

    /// Records that the host permitted the stream to continue.
    public func continueStream() {
        continueStreamCallCount += 1
        pauseGate?.continueStream()
    }

    /// Records analysis teardown.
    public func endAnalysis() {
        endAnalysisCallCount += 1
        invalidateActiveStream()
    }

    isolated deinit {
        pauseGate?.cancel()
        activeContinuation?.finish()
        forwardingTask?.cancel()
    }

    private func invalidateActiveStream() {
        generation &+= 1
        pauseGate?.cancel()
        pauseGate = nil
        activeContinuation?.finish()
        activeContinuation = nil
        forwardingTask?.cancel()
        forwardingTask = nil
    }

    private func invalidateActiveStream(ifCurrent generation: UInt) {
        guard self.generation == generation else { return }
        invalidateActiveStream()
    }

    private func clearActiveStream(ifCurrent generation: UInt) {
        guard self.generation == generation else { return }
        pauseGate?.cancel()
        pauseGate = nil
        activeContinuation = nil
        forwardingTask = nil
    }

    private func terminate(_ source: EventStream) async {
        let consumer = Task { @MainActor in
            do {
                for try await _ in source {
                    guard !Task.isCancelled else { return }
                }
            } catch {
                // Cancellation is the intended teardown path.
            }
        }
        consumer.cancel()
        await consumer.value
    }
}

@MainActor
private final class MockStreamPauseGate {
    private enum State: Equatable {
        case running
        case paused
        case cancelled
    }

    private var state = State.running
    private var waiter: CheckedContinuation<Void, Never>?

    func preparePause() -> Bool {
        guard state == .running, !Task.isCancelled else { return false }
        state = .paused
        return true
    }

    func waitUntilContinued() async -> Bool {
        switch state {
        case .running:
            return !Task.isCancelled
        case .cancelled:
            return false
        case .paused:
            break
        }

        await withCheckedContinuation { continuation in
            guard state == .paused, !Task.isCancelled else {
                continuation.resume()
                return
            }
            waiter = continuation
        }

        return state == .running && !Task.isCancelled
    }

    func continueStream() {
        guard state == .paused else { return }
        state = .running
        let waiter = waiter
        self.waiter = nil
        waiter?.resume()
    }

    func cancel() {
        guard state != .cancelled else { return }
        state = .cancelled
        let waiter = waiter
        self.waiter = nil
        waiter?.resume()
    }
}
