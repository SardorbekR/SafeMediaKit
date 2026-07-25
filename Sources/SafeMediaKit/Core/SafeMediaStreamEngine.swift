/// A lifecycle or decision emitted while monitoring live video.
///
/// The event must remain in the current process and on device. Do not send it
/// to analytics, remote logging, synced storage, or report payloads.
public enum SafeMediaStreamEvent: Sendable, Hashable {
    /// The host must conceal the stream before analysis is detached or starts.
    ///
    /// This is the first event for every start that proceeds, including
    /// restarts. A task cancelled before calling `start` receives no events.
    case preparing

    /// The analyzer attached successfully and monitoring has begun.
    ///
    /// This does not mean that every frame, or any frame, was classified safe.
    case ready

    /// A policy decision caused by a verdict, unavailability, or failure.
    case decision(SafeMediaDecision)
}

/// Starts and supervises one live-video analysis session without using a
/// verdict cache.
@MainActor
public final class SafeMediaStreamEngine {
    private let analyzer: any SafeMediaStreamAnalyzing
    private var activeSession: SafeMediaStreamSession?

    /// Creates a stream engine backed by one analyzer.
    ///
    /// Stream engines intentionally accept no cache or cache key. Every start
    /// that reaches preflight performs a fresh availability check and, when
    /// available, a fresh attachment.
    public init(analyzer: any SafeMediaStreamAnalyzing) {
        self.analyzer = analyzer
    }

    /// Starts monitoring and applies every event synchronously on the main
    /// actor.
    ///
    /// The method never throws. Unavailability produces one decision using
    /// `policy.unavailableAction`. After a setup error, the engine refreshes
    /// availability and uses the unavailable action if it changed to
    /// unavailable; otherwise setup and mid-stream errors use
    /// `policy.failureAction`. Unexpected normal completion is also treated as
    /// analysis failure because the host stream may still be visible. Explicit
    /// cancellation ends silently.
    ///
    /// The `applying` closure is the fail-closed UI boundary. Conceal, blur, or
    /// interrupt the stream directly in the closure before returning. Do not
    /// defer the intervention into another task. Apple's attached capture and
    /// decompression pipelines automatically censor video after detection;
    /// the closure synchronizes the host interface with the SafeMediaKit event.
    /// Custom analyzers must pause or censor their pipeline before yielding a
    /// sensitive verdict.
    ///
    /// For decisions received after attachment, `.allow` and `.muteAudio`
    /// resume a paused stream automatically, `.blur` and `.blurWithReveal`
    /// wait for ``SafeMediaStreamSession/continueStream()``, and `.block` and
    /// `.interruptVideo` end monitoring. Unavailability and setup-failure
    /// decisions finish immediately because no analyzer is attached.
    ///
    /// For a start that proceeds, the first event is always
    /// ``SafeMediaStreamEvent/preparing``. Conceal the stream in that callback
    /// before the engine detaches a previous session or begins availability
    /// preflight for the replacement. A task already cancelled at entry
    /// receives a finished session and no events.
    ///
    /// The engine retains its active session until it ends or is replaced, so
    /// dropping the returned handle does not cancel monitoring.
    ///
    /// - Parameters:
    ///   - policy: The policy used to translate stream verdicts.
    ///   - handler: The mandatory, synchronous event handler.
    /// - Returns: A session used to resume or cancel monitoring.
    public func start(
        policy: SafeMediaPolicy,
        applying handler: @escaping @MainActor @Sendable (
            SafeMediaStreamEvent
        ) -> Void
    ) async -> SafeMediaStreamSession {
        guard !Task.isCancelled else {
            return makeFinishedSession()
        }

        let lifecycle = SafeMediaStreamLifecycle(analyzer: analyzer)
        let session = SafeMediaStreamSession(lifecycle: lifecycle)
        guard lifecycle.publish(.preparing, applying: handler) else {
            lifecycle.finish()
            return session
        }

        let previousTask = activeSession?.cancelForReplacement()
        activeSession = session

        let monitoringTask = Task { @MainActor [
            weak self,
            weak session,
            analyzer,
            lifecycle,
            handler,
            previousTask
        ] in
            defer {
                lifecycle.finish()
                session?.monitoringDidFinish()
                self?.clearActiveSession(ifUsing: lifecycle)
            }

            await previousTask?.value
            guard !Task.isCancelled, !lifecycle.isFinished else { return }

            let currentAvailability = await analyzer.availability()
            guard !Task.isCancelled, !lifecycle.isFinished else { return }

            if case .unavailable = currentAvailability {
                let verdict = SafeMediaVerdict(
                    sensitivity: .unknown,
                    contentTypes: [],
                    guidance: .none,
                    availability: currentAvailability
                )
                let decision = Self.decision(for: verdict, policy: policy)
                lifecycle.publish(.decision(decision), applying: handler)
                return
            }

            guard lifecycle.markAnalysisStarting() else { return }

            let analysisEvents: AsyncThrowingStream<
                SafeMediaVerdict,
                any Error
            >

            do {
                analysisEvents = try await analyzer.startAnalysis()
            } catch {
                // A conformer may have partially attached before throwing.
                // Tear it down before another async preflight so cleanup can
                // never depend on that preflight returning.
                analyzer.endAnalysis()
                lifecycle.markAnalysisStartFailed()
                guard !Task.isCancelled, !lifecycle.isFinished else { return }

                let refreshedAvailability = await analyzer.availability()
                guard !Task.isCancelled, !lifecycle.isFinished else { return }

                if case .unavailable = refreshedAvailability {
                    let verdict = SafeMediaVerdict(
                        sensitivity: .unknown,
                        contentTypes: [],
                        guidance: .none,
                        availability: refreshedAvailability
                    )
                    let decision = Self.decision(for: verdict, policy: policy)
                    lifecycle.publish(.decision(decision), applying: handler)
                    return
                }

                let decision = SafeMediaEngine.failureDecision(
                    context: .liveVideo,
                    policy: policy
                )
                lifecycle.publish(.decision(decision), applying: handler)
                return
            }

            guard !Task.isCancelled,
                  lifecycle.markAnalysisStarted() else {
                // A conformer may finish attaching after an earlier teardown
                // request. End again so a late attachment cannot outlive the
                // cancelled session. Protocol conformers make repeated ends
                // safe.
                analyzer.endAnalysis()
                return
            }

            guard lifecycle.publish(.ready, applying: handler) else { return }

            do {
                for try await verdict in analysisEvents {
                    guard !Task.isCancelled else { return }

                    let decision = Self.decision(for: verdict, policy: policy)
                    let requiresContinuation = verdict.sensitivity == .sensitive
                        || decision.action == .blur
                        || decision.action == .blurWithReveal
                    guard !requiresContinuation || lifecycle.pause(
                        shouldContinueAnalyzer: verdict.sensitivity == .sensitive
                    ) else {
                        return
                    }
                    guard lifecycle.publish(
                        .decision(decision),
                        applying: handler
                    ) else {
                        return
                    }

                    switch decision.action {
                    case .allow, .muteAudio:
                        if requiresContinuation {
                            lifecycle.continueStream()
                        }
                    case .block, .interruptVideo:
                        return
                    case .blur, .blurWithReveal:
                        guard await lifecycle.waitUntilContinued() else {
                            return
                        }
                    }
                }

                // A live stream is expected to remain monitored until the
                // host cancels or an intervention terminates the session. If
                // the analyzer disappears without either signal, fail closed
                // before detaching so a revealed stream cannot continue
                // unmonitored.
                guard !Task.isCancelled, !lifecycle.isFinished else { return }
                await Self.applyTerminalFailure(
                    policy: policy,
                    lifecycle: lifecycle,
                    handler: handler
                )
            } catch {
                guard !Task.isCancelled else { return }
                await Self.applyTerminalFailure(
                    policy: policy,
                    lifecycle: lifecycle,
                    handler: handler
                )
            }
        }

        session.install(monitoringTask)
        return session
    }

    private static func decision(
        for verdict: SafeMediaVerdict,
        policy: SafeMediaPolicy
    ) -> SafeMediaDecision {
        let finiteDecision = SafeMediaEngine.decision(
            for: verdict,
            context: .liveVideo,
            policy: policy
        )

        guard verdict.sensitivity == .sensitive else {
            return finiteDecision
        }

        return SafeMediaDecision(
            action: policy.streamSensitiveAction ?? policy.sensitiveAction,
            verdict: verdict,
            context: .liveVideo,
            policy: policy,
            reason: finiteDecision.reason
        )
    }

    private static func applyTerminalFailure(
        policy: SafeMediaPolicy,
        lifecycle: SafeMediaStreamLifecycle,
        handler: @MainActor @Sendable (SafeMediaStreamEvent) -> Void
    ) async {
        guard lifecycle.pause(shouldContinueAnalyzer: false) else { return }

        let decision = SafeMediaEngine.failureDecision(
            context: .liveVideo,
            policy: policy
        )
        guard lifecycle.publish(.decision(decision), applying: handler) else {
            return
        }

        switch decision.action {
        case .allow, .muteAudio:
            lifecycle.continueStream()
        case .block, .interruptVideo:
            return
        case .blur, .blurWithReveal:
            _ = await lifecycle.waitUntilContinued()
        }
    }

    private func makeFinishedSession() -> SafeMediaStreamSession {
        let lifecycle = SafeMediaStreamLifecycle(analyzer: analyzer)
        lifecycle.finish()
        return SafeMediaStreamSession(lifecycle: lifecycle)
    }

    private func clearActiveSession(ifUsing lifecycle: SafeMediaStreamLifecycle) {
        guard activeSession?.uses(lifecycle) == true else { return }
        activeSession = nil
    }
}

/// A running or completed live-video analysis session.
///
/// Use the mandatory handler passed to
/// ``SafeMediaStreamEngine/start(policy:applying:)`` for every UI intervention.
@MainActor
public final class SafeMediaStreamSession {
    private let lifecycle: SafeMediaStreamLifecycle
    private var monitoringTask: Task<Void, Never>?

    fileprivate init(lifecycle: SafeMediaStreamLifecycle) {
        self.lifecycle = lifecycle
    }

    /// Resumes monitoring after a paused decision.
    ///
    /// Call this after an explicit reveal or other host-approved resume path
    /// has synchronously prepared the interface for subsequent frames. If the
    /// current verdict was sensitive, this also permits the analyzer's
    /// configured stream to continue. The engine resumes `.allow` and
    /// `.muteAudio` decisions automatically.
    public func continueStream() {
        lifecycle.continueStream()
    }

    /// Cancels monitoring and ends analysis immediately. Repeated calls are
    /// safe.
    ///
    /// Conceal or stop the host media pipeline synchronously before calling
    /// this method. Detaching an Apple analyzer can remove its native
    /// censorship, and cancellation intentionally produces no decision event.
    public func cancel() {
        monitoringTask?.cancel()
        lifecycle.finish()
    }

    /// Cancels monitoring, ends analysis, and waits for the monitoring task to
    /// finish. Repeated calls are safe.
    ///
    /// Conceal or stop the host media pipeline synchronously before calling
    /// this method. Detaching an Apple analyzer can remove its native
    /// censorship, and cancellation intentionally produces no decision event.
    public func cancelAndWait() async {
        cancel()
        await waitForCompletion()
    }

    /// Waits for monitoring to finish without cancelling it.
    public func waitForCompletion() async {
        await monitoringTask?.value
        monitoringTask = nil
    }

    fileprivate func install(_ task: Task<Void, Never>) {
        monitoringTask = task
    }

    fileprivate func cancelForReplacement() -> Task<Void, Never>? {
        let task = monitoringTask
        cancel()
        return task
    }

    fileprivate func monitoringDidFinish() {
        monitoringTask = nil
    }

    fileprivate func uses(_ lifecycle: SafeMediaStreamLifecycle) -> Bool {
        self.lifecycle === lifecycle
    }

    isolated deinit {
        monitoringTask?.cancel()
        lifecycle.finish()
    }
}

@MainActor
private final class SafeMediaStreamLifecycle {
    private enum AnalysisState: Equatable {
        case idle
        case starting
        case running
        case paused(shouldContinueAnalyzer: Bool)
        case finished
    }

    private let analyzer: any SafeMediaStreamAnalyzing
    private var analysisState = AnalysisState.idle
    private var continuationWaiter: CheckedContinuation<Void, Never>?

    var isFinished: Bool {
        analysisState == .finished
    }

    init(analyzer: any SafeMediaStreamAnalyzing) {
        self.analyzer = analyzer
    }

    func markAnalysisStarting() -> Bool {
        guard analysisState == .idle, !Task.isCancelled else { return false }
        analysisState = .starting
        return true
    }

    func markAnalysisStarted() -> Bool {
        guard analysisState == .starting, !Task.isCancelled else { return false }
        analysisState = .running
        return true
    }

    func markAnalysisStartFailed() {
        guard analysisState == .starting else { return }
        analysisState = .idle
    }

    func pause(shouldContinueAnalyzer: Bool) -> Bool {
        guard analysisState == .running, !Task.isCancelled else { return false }
        analysisState = .paused(
            shouldContinueAnalyzer: shouldContinueAnalyzer
        )
        return true
    }

    @discardableResult
    func publish(
        _ event: SafeMediaStreamEvent,
        applying handler: @MainActor @Sendable (SafeMediaStreamEvent) -> Void
    ) -> Bool {
        guard analysisState != .finished, !Task.isCancelled else {
            return false
        }
        handler(event)
        return analysisState != .finished && !Task.isCancelled
    }

    func continueStream() {
        guard case .paused(let shouldContinueAnalyzer) = analysisState else {
            return
        }
        analysisState = .running
        if shouldContinueAnalyzer {
            analyzer.continueStream()
        }
        let waiter = continuationWaiter
        continuationWaiter = nil
        waiter?.resume()
    }

    func waitUntilContinued() async -> Bool {
        guard case .paused = analysisState, !Task.isCancelled else {
            return isRunning && !Task.isCancelled
        }

        await withCheckedContinuation { continuation in
            guard case .paused = analysisState, !Task.isCancelled else {
                continuation.resume()
                return
            }
            continuationWaiter = continuation
        }

        return isRunning && !Task.isCancelled
    }

    private var isRunning: Bool {
        if case .running = analysisState {
            return true
        }
        return false
    }

    func finish() {
        switch analysisState {
        case .starting, .running, .paused:
            analysisState = .finished
            let waiter = continuationWaiter
            continuationWaiter = nil
            waiter?.resume()
            analyzer.endAnalysis()
        case .idle:
            analysisState = .finished
        case .finished:
            break
        }
    }
}
