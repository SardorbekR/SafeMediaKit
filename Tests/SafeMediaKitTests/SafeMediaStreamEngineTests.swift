import SafeMediaKit
import SafeMediaKitTesting
import XCTest

@MainActor
final class SafeMediaStreamEngineTests: XCTestCase {
    func testSensitiveVerdictIsAppliedOnMainActorWithGuidance() async {
        let (eventStream, continuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let analyzer = MockStreamAnalyzer { eventStream }
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let readyApplied = expectation(description: "ready applied")
        let decisionApplied = expectation(description: "sensitive decision applied")
        var appliedEvents: [SafeMediaStreamEvent] = []

        let session = await engine.start(policy: .teenMessaging) { event in
            MainActor.assertIsolated()
            appliedEvents.append(event)

            switch event {
            case .preparing:
                break
            case .ready:
                readyApplied.fulfill()
            case .decision:
                decisionApplied.fulfill()
            }
        }

        XCTAssertEqual(appliedEvents, [.preparing])
        await fulfillment(of: [readyApplied], timeout: 5)
        XCTAssertEqual(appliedEvents, [.preparing, .ready])

        continuation.yield(.mockSensitiveVideo)
        await fulfillment(of: [decisionApplied], timeout: 5)

        guard case .decision(let decision) = appliedEvents.last else {
            return XCTFail("Expected a decision event")
        }

        XCTAssertEqual(decision.action, .blurWithReveal)
        XCTAssertEqual(decision.context, .liveVideo)
        XCTAssertEqual(decision.reason, .sensitiveDetected)
        XCTAssertEqual(decision.verdict.contentTypes, [.nudity])
        XCTAssertTrue(decision.verdict.guidance.shouldIndicateSensitivity)
        XCTAssertTrue(decision.verdict.guidance.shouldInterruptVideo)
        XCTAssertTrue(decision.verdict.guidance.shouldMuteAudio)
        XCTAssertEqual(analyzer.continueStreamCallCount, 0)

        await cancelAndWait(session)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
    }

    func testUnavailablePathUsesEachPresetWithoutStartingAnalysis() async {
        let cases: [(SafeMediaPolicy, SafeMediaAction)] = [
            (.adultMinimal, .allow),
            (.teenMessaging, .blurWithReveal),
            (.childStrict, .block)
        ]

        for (policy, expectedAction) in cases {
            let analyzer = MockStreamAnalyzer(
                events: [],
                availability: .unavailable(.analysisPolicyDisabled)
            )
            let engine = SafeMediaStreamEngine(analyzer: analyzer)
            let decisionApplied = expectation(
                description: "unavailable decision for \(expectedAction)"
            )
            var appliedEvents: [SafeMediaStreamEvent] = []

            let session = await engine.start(policy: policy) { event in
                appliedEvents.append(event)
                if case .decision = event {
                    decisionApplied.fulfill()
                }
            }

            await fulfillment(of: [decisionApplied], timeout: 5)
            await waitForCompletion(of: session)

            XCTAssertEqual(analyzer.availabilityCallCount, 1)
            XCTAssertEqual(analyzer.startAnalysisCallCount, 0)
            XCTAssertEqual(analyzer.endAnalysisCallCount, 0)
            XCTAssertEqual(appliedEvents.count, 2)
            XCTAssertEqual(appliedEvents.first, .preparing)

            guard case .decision(let decision) = appliedEvents.last else {
                return XCTFail("Expected an unavailable decision")
            }

            XCTAssertEqual(decision.action, expectedAction)
            XCTAssertEqual(decision.reason, .unavailableByPolicy)
            XCTAssertEqual(
                decision.verdict.availability,
                .unavailable(.analysisPolicyDisabled)
            )
        }
    }

    func testStreamSensitiveActionUsesEachPresetOverride() async {
        let cases: [(SafeMediaPolicy, SafeMediaAction)] = [
            (.adultMinimal, .allow),
            (.teenMessaging, .blurWithReveal),
            (.childStrict, .interruptVideo)
        ]

        for (policy, expectedAction) in cases {
            let (eventStream, continuation) = MockStreamAnalyzer.EventStream
                .makeStream(bufferingPolicy: .unbounded)
            let analyzer = MockStreamAnalyzer { eventStream }
            let engine = SafeMediaStreamEngine(analyzer: analyzer)
            let readyApplied = expectation(
                description: "ready for \(expectedAction)"
            )
            let decisionApplied = expectation(
                description: "decision for \(expectedAction)"
            )
            let nextDecisionApplied: XCTestExpectation? = switch expectedAction {
            case .allow, .blurWithReveal:
                expectation(description: "next decision for \(expectedAction)")
            case .blur, .block, .interruptVideo, .muteAudio:
                nil
            }
            var appliedDecisions: [SafeMediaDecision] = []

            let session = await engine.start(policy: policy) { event in
                if event == .ready {
                    readyApplied.fulfill()
                }
                guard case .decision(let decision) = event,
                      decision.reason != .analysisFailed else { return }
                appliedDecisions.append(decision)
                if appliedDecisions.count == 1 {
                    decisionApplied.fulfill()
                } else if appliedDecisions.count == 2 {
                    nextDecisionApplied?.fulfill()
                }
            }

            await fulfillment(of: [readyApplied], timeout: 5)
            continuation.yield(.mockSensitiveVideo)
            await fulfillment(of: [decisionApplied], timeout: 5)

            XCTAssertEqual(appliedDecisions.first?.action, expectedAction)

            switch expectedAction {
            case .allow:
                continuation.yield(.mockSafe)
                await fulfillment(of: [nextDecisionApplied!], timeout: 5)
                XCTAssertEqual(appliedDecisions.last?.reason, .safe)
                XCTAssertEqual(analyzer.continueStreamCallCount, 1)
                await cancelAndWait(session)
            case .blurWithReveal:
                continuation.yield(.mockSafe)
                session.continueStream()
                await fulfillment(of: [nextDecisionApplied!], timeout: 5)
                XCTAssertEqual(appliedDecisions.last?.reason, .safe)
                XCTAssertEqual(analyzer.continueStreamCallCount, 1)
                await cancelAndWait(session)
            case .interruptVideo:
                await waitForCompletion(of: session)
                XCTAssertEqual(analyzer.continueStreamCallCount, 0)
            case .blur, .block, .muteAudio:
                XCTFail("Unexpected preset stream action: \(expectedAction)")
                await cancelAndWait(session)
            }

            XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
        }
    }

    func testCustomPolicyInheritsFiniteSensitiveActionForStreams() async {
        let policy = SafeMediaPolicy(
            sensitiveAction: .muteAudio,
            unknownAction: .allow,
            unavailableAction: .allow,
            failureAction: .allow,
            allowReveal: false,
            allowReport: false
        )
        let (eventStream, continuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let analyzer = MockStreamAnalyzer { eventStream }
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let readyApplied = expectation(description: "custom policy ready")
        let decisionApplied = expectation(description: "custom policy decision")
        var action: SafeMediaAction?

        let session = await engine.start(policy: policy) { event in
            if event == .ready {
                readyApplied.fulfill()
            }
            guard case .decision(let decision) = event,
                  decision.reason == .sensitiveDetected else { return }
            action = decision.action
            decisionApplied.fulfill()
        }

        await fulfillment(of: [readyApplied], timeout: 5)
        continuation.yield(.mockSensitiveVideo)
        await fulfillment(of: [decisionApplied], timeout: 5)
        await cancelAndWait(session)

        XCTAssertEqual(action, .muteAudio)
        XCTAssertEqual(analyzer.continueStreamCallCount, 1)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
    }

    func testSetupFailureEmitsFailureDecisionWithoutReady() async {
        let analyzer = MockStreamAnalyzer {
            throw SafeMediaError.analysisFailed("setup")
        }
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let failureApplied = expectation(description: "setup failure applied")
        var appliedEvents: [SafeMediaStreamEvent] = []

        let session = await engine.start(policy: .childStrict) { event in
            appliedEvents.append(event)
            if case .decision = event {
                failureApplied.fulfill()
            }
        }

        await fulfillment(of: [failureApplied], timeout: 5)
        await waitForCompletion(of: session)

        XCTAssertEqual(appliedEvents.count, 2)
        XCTAssertEqual(appliedEvents.first, .preparing)
        guard case .decision(let decision) = appliedEvents.last else {
            return XCTFail("Expected a setup-failure decision")
        }

        XCTAssertEqual(decision.action, .block)
        XCTAssertEqual(decision.reason, .analysisFailed)
        XCTAssertEqual(analyzer.startAnalysisCallCount, 1)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
    }

    func testMidStreamFailureFollowsVerdictAndCompletesPermissivePolicy() async {
        let (eventStream, continuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let analyzer = MockStreamAnalyzer { eventStream }
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let readyApplied = expectation(description: "ready applied")
        let safeApplied = expectation(description: "safe verdict applied")
        let failureApplied = expectation(description: "failure applied")
        var decisions: [SafeMediaDecision] = []

        let session = await engine.start(policy: .adultMinimal) { event in
            switch event {
            case .preparing:
                break
            case .ready:
                readyApplied.fulfill()
            case .decision(let decision):
                decisions.append(decision)
                if decision.reason == .analysisFailed {
                    failureApplied.fulfill()
                } else {
                    safeApplied.fulfill()
                }
            }
        }

        await fulfillment(of: [readyApplied], timeout: 5)
        continuation.yield(.mockSafe)
        await fulfillment(of: [safeApplied], timeout: 5)
        continuation.finish(throwing: SafeMediaError.analysisFailed("midstream"))
        await fulfillment(of: [failureApplied], timeout: 5)
        await waitForCompletion(of: session)

        XCTAssertEqual(decisions.map(\.reason), [.safe, .analysisFailed])
        XCTAssertEqual(decisions.map(\.action), [.allow, .allow])
        XCTAssertEqual(analyzer.continueStreamCallCount, 0)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
    }

    func testUnknownRevealDoesNotResumeAnalyzerBeforeBufferedSensitiveVerdict() async {
        let (eventStream, continuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let analyzer = UngatedStreamAnalyzer(
            stream: eventStream,
            continuation: continuation
        )
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let unknownApplied = expectation(description: "unknown blur applied")
        let sensitiveApplied = expectation(description: "sensitive blur applied")
        var reasons: [SafeMediaDecisionReason] = []

        let session = await engine.start(policy: .teenMessaging) { event in
            guard case .decision(let decision) = event else { return }
            reasons.append(decision.reason)
            if decision.reason == .unknownByPolicy {
                unknownApplied.fulfill()
            } else if decision.reason == .sensitiveDetected {
                sensitiveApplied.fulfill()
            }
        }

        continuation.yield(
            SafeMediaVerdict(
                sensitivity: .unknown,
                contentTypes: [],
                guidance: .none,
                availability: .available
            )
        )
        continuation.yield(.mockSensitiveVideo)
        await fulfillment(of: [unknownApplied], timeout: 5)

        session.continueStream()
        await fulfillment(of: [sensitiveApplied], timeout: 5)

        XCTAssertEqual(reasons, [.unknownByPolicy, .sensitiveDetected])
        XCTAssertEqual(analyzer.continueStreamCallCount, 0)
        await cancelAndWait(session)
    }

    func testCancellationEndsSilentlyAndTerminatesUpstream() async {
        let (eventStream, continuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let upstreamTerminated = expectation(description: "upstream terminated")
        continuation.onTermination = { @Sendable _ in
            upstreamTerminated.fulfill()
        }
        let analyzer = MockStreamAnalyzer { eventStream }
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let readyApplied = expectation(description: "ready applied")
        var appliedEvents: [SafeMediaStreamEvent] = []

        let session = await engine.start(policy: .teenMessaging) { event in
            appliedEvents.append(event)
            if event == .ready {
                readyApplied.fulfill()
            }
        }

        await fulfillment(of: [readyApplied], timeout: 5)
        await cancelAndWait(session)
        await fulfillment(of: [upstreamTerminated], timeout: 5)

        XCTAssertEqual(appliedEvents, [.preparing, .ready])
        XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
    }

    func testCancellationDoesNotDrainBufferedVerdicts() async {
        let (eventStream, continuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let analyzer = MockStreamAnalyzer { eventStream }
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let holder = StreamSessionHolder()
        let readyApplied = expectation(description: "ready applied")
        let firstDecisionApplied = expectation(description: "first decision applied")
        var decisionCount = 0

        holder.session = await engine.start(policy: .adultMinimal) { event in
            if event == .ready {
                readyApplied.fulfill()
            }

            guard case .decision = event else { return }
            decisionCount += 1

            if decisionCount == 1 {
                holder.session?.cancel()
                firstDecisionApplied.fulfill()
            }
        }

        await fulfillment(of: [readyApplied], timeout: 5)
        continuation.yield(.mockSafe)
        continuation.yield(.mockSensitiveVideo)
        continuation.yield(.mockSafe)
        await fulfillment(of: [firstDecisionApplied], timeout: 5)
        await waitForCompletion(of: holder.session)

        XCTAssertEqual(decisionCount, 1)
        XCTAssertEqual(analyzer.continueStreamCallCount, 0)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
    }

    func testEveryStartPerformsFreshAnalysisWithoutCaching() async {
        var factoryCallCount = 0
        let analyzer = MockStreamAnalyzer {
            factoryCallCount += 1
            let verdict: SafeMediaVerdict = factoryCallCount == 1
                ? .mockSafe
                : .mockSensitiveVideo
            return MockStreamAnalyzer.EventStream { continuation in
                continuation.yield(verdict)
            }
        }
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        var sensitivities: [SafeMediaSensitivity] = []

        for _ in 0..<2 {
            let decisionApplied = expectation(description: "fresh decision")
            let session = await engine.start(policy: .adultMinimal) { event in
                guard case .decision(let decision) = event else { return }
                sensitivities.append(decision.verdict.sensitivity)
                decisionApplied.fulfill()
            }
            await fulfillment(of: [decisionApplied], timeout: 5)
            await cancelAndWait(session)
        }

        XCTAssertEqual(sensitivities, [.safe, .sensitive])
        XCTAssertEqual(analyzer.availabilityCallCount, 2)
        XCTAssertEqual(analyzer.startAnalysisCallCount, 2)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 2)
    }

    func testReplacementConcealsThenStopsPreviousSession() async {
        let (firstStream, firstContinuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let (secondStream, secondContinuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let firstTerminated = expectation(description: "first stream terminated")
        firstContinuation.onTermination = { @Sendable _ in
            firstTerminated.fulfill()
        }

        var factoryCallCount = 0
        let baseAnalyzer = MockStreamAnalyzer {
            factoryCallCount += 1
            return factoryCallCount == 1 ? firstStream : secondStream
        }
        let analyzer = ReplacementTraceAnalyzer(base: baseAnalyzer)
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let firstReady = expectation(description: "first ready")
        let secondReady = expectation(description: "second ready")
        let secondDecision = expectation(description: "second decision")
        var firstEvents: [SafeMediaStreamEvent] = []
        var secondEvents: [SafeMediaStreamEvent] = []

        _ = await engine.start(policy: .teenMessaging) { event in
            firstEvents.append(event)
            if event == .ready {
                firstReady.fulfill()
            }
        }
        await fulfillment(of: [firstReady], timeout: 5)

        let secondSession = await engine.start(policy: .teenMessaging) { event in
            secondEvents.append(event)
            if event == .preparing {
                analyzer.trace.append(.concealed)
            }
            if event == .ready {
                secondReady.fulfill()
            }
            if case .decision = event {
                secondDecision.fulfill()
            }
        }

        XCTAssertEqual(secondEvents, [.preparing])
        XCTAssertEqual(analyzer.trace, [.concealed, .analysisEnded])
        await fulfillment(of: [firstTerminated, secondReady], timeout: 5)

        if case .terminated = firstContinuation.yield(.mockSensitiveVideo) {
            // Expected: replacement invalidated the old source.
        } else {
            XCTFail("Expected the replaced source to reject new verdicts")
        }

        secondContinuation.yield(.mockSensitiveVideo)
        await fulfillment(of: [secondDecision], timeout: 5)

        XCTAssertEqual(firstEvents, [.preparing, .ready])
        XCTAssertEqual(secondEvents.count, 3)
        XCTAssertEqual(Array(secondEvents.prefix(2)), [.preparing, .ready])
        XCTAssertEqual(baseAnalyzer.startAnalysisCallCount, 2)

        await cancelAndWait(secondSession)
        XCTAssertEqual(baseAnalyzer.endAnalysisCallCount, 2)
    }

    func testAlreadyCancelledStartDoesNotReplaceActiveSession() async {
        let (eventStream, continuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let analyzer = MockStreamAnalyzer { eventStream }
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let readyApplied = expectation(description: "active session ready")
        let activeDecision = expectation(description: "active session decision")
        var activeEvents: [SafeMediaStreamEvent] = []
        var cancelledStartEvents: [SafeMediaStreamEvent] = []

        let activeSession = await engine.start(policy: .adultMinimal) { event in
            activeEvents.append(event)
            if event == .ready {
                readyApplied.fulfill()
            }
            if case .decision = event {
                activeDecision.fulfill()
            }
        }
        await fulfillment(of: [readyApplied], timeout: 5)

        let cancelledStartFinished = expectation(
            description: "already-cancelled start finished"
        )
        let cancelledTask = Task { @MainActor in
            defer { cancelledStartFinished.fulfill() }
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return await engine.start(policy: .childStrict) { event in
                cancelledStartEvents.append(event)
            }
        }
        let cancelledStartResult = await XCTWaiter.fulfillment(
            of: [cancelledStartFinished],
            timeout: 5
        )
        guard cancelledStartResult == .completed else {
            cancelledTask.cancel()
            XCTFail("Timed out waiting for the already-cancelled start")
            await cancelAndWait(activeSession)
            return
        }
        let cancelledSession = await cancelledTask.value

        XCTAssertTrue(cancelledStartEvents.isEmpty)
        continuation.yield(.mockSafe)
        await fulfillment(of: [activeDecision], timeout: 5)
        XCTAssertEqual(activeEvents.count, 3)

        await cancelAndWait(cancelledSession)
        await cancelAndWait(activeSession)
        XCTAssertEqual(analyzer.startAnalysisCallCount, 1)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
    }

    func testEngineRetainsActiveSessionWhenCallerDropsHandle() async {
        let (eventStream, continuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let analyzer = MockStreamAnalyzer { eventStream }
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let readyApplied = expectation(description: "ready applied")
        let decisionApplied = expectation(description: "decision applied")

        _ = await engine.start(policy: .teenMessaging) { event in
            if event == .ready {
                readyApplied.fulfill()
            }
            if case .decision = event {
                decisionApplied.fulfill()
            }
        }

        await fulfillment(of: [readyApplied], timeout: 5)
        continuation.yield(.mockSensitiveVideo)
        await fulfillment(of: [decisionApplied], timeout: 5)

        let cleanupSession = await engine.start(policy: .adultMinimal) { _ in }
        await cancelAndWait(cleanupSession)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
    }

    func testUnexpectedNormalCompletionFailsClosed() async {
        let (eventStream, continuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let analyzer = MockStreamAnalyzer { eventStream }
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let readyApplied = expectation(description: "ready applied")
        let failureApplied = expectation(description: "failure applied")
        var reasons: [SafeMediaDecisionReason] = []

        let session = await engine.start(policy: .childStrict) { event in
            if event == .ready {
                readyApplied.fulfill()
            }
            if case .decision(let decision) = event {
                reasons.append(decision.reason)
                failureApplied.fulfill()
            }
        }

        await fulfillment(of: [readyApplied], timeout: 5)
        continuation.finish()
        await fulfillment(of: [failureApplied], timeout: 5)
        await waitForCompletion(of: session)

        XCTAssertEqual(reasons, [.analysisFailed])
        XCTAssertEqual(analyzer.continueStreamCallCount, 0)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
    }

    func testBufferedSafeVerdictWaitsForExplicitReveal() async {
        let (eventStream, continuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        continuation.yield(.mockSensitiveVideo)
        continuation.yield(.mockSafe)
        let analyzer = UngatedStreamAnalyzer(
            stream: eventStream,
            continuation: continuation
        )
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let blurApplied = expectation(description: "blur applied")
        let safeApplied = expectation(description: "safe applied")
        var actions: [SafeMediaAction] = []

        let session = await engine.start(policy: .teenMessaging) { event in
            guard case .decision(let decision) = event else { return }
            actions.append(decision.action)
            if decision.action == .blurWithReveal {
                blurApplied.fulfill()
            } else if decision.reason == .safe {
                safeApplied.fulfill()
            }
        }

        await fulfillment(of: [blurApplied], timeout: 5)
        XCTAssertEqual(actions, [.blurWithReveal])
        XCTAssertEqual(analyzer.continueStreamCallCount, 0)

        session.continueStream()
        await fulfillment(of: [safeApplied], timeout: 5)
        await cancelAndWait(session)

        XCTAssertEqual(actions, [.blurWithReveal, .allow])
        XCTAssertEqual(analyzer.continueStreamCallCount, 1)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
    }

    func testManualContinueInsideAllowHandlerDoesNotResumeTwice() async {
        let (eventStream, continuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let analyzer = UngatedStreamAnalyzer(
            stream: eventStream,
            continuation: continuation
        )
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let holder = StreamSessionHolder()
        let readyApplied = expectation(description: "ready applied")
        let allowApplied = expectation(description: "allow applied")

        holder.session = await engine.start(policy: .adultMinimal) { event in
            if event == .ready {
                readyApplied.fulfill()
            }
            if case .decision(let decision) = event,
               decision.action == .allow {
                holder.session?.continueStream()
                allowApplied.fulfill()
            }
        }

        await fulfillment(of: [readyApplied], timeout: 5)
        continuation.yield(.mockSensitiveVideo)
        await fulfillment(of: [allowApplied], timeout: 5)

        XCTAssertEqual(analyzer.continueStreamCallCount, 1)
        await cancelAndWait(holder.session)
    }

    func testSetupFailureUsesRefreshedUnavailableState() async {
        let analyzer = AvailabilityRaceStreamAnalyzer()
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let policy = SafeMediaPolicy(
            sensitiveAction: .allow,
            unknownAction: .allow,
            unavailableAction: .block,
            failureAction: .allow,
            allowReveal: false,
            allowReport: false
        )
        let decisionApplied = expectation(description: "unavailable decision applied")
        var appliedDecision: SafeMediaDecision?

        let session = await engine.start(policy: policy) { event in
            guard case .decision(let decision) = event else { return }
            appliedDecision = decision
            decisionApplied.fulfill()
        }

        await fulfillment(of: [decisionApplied], timeout: 5)
        await waitForCompletion(of: session)

        XCTAssertEqual(analyzer.availabilityCallCount, 2)
        XCTAssertEqual(appliedDecision?.action, .block)
        XCTAssertEqual(appliedDecision?.reason, .unavailableByPolicy)
        XCTAssertEqual(
            appliedDecision?.verdict.availability,
            .unavailable(.analysisPolicyDisabled)
        )
    }

    func testSetupFailureDetachesBeforeRefreshingAvailability() async {
        let analyzer = PartiallyAttachingFailureAnalyzer()
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let failureApplied = expectation(description: "failure applied")

        let session = await engine.start(policy: .childStrict) { event in
            guard case .decision(let decision) = event,
                  decision.reason == .analysisFailed else { return }
            failureApplied.fulfill()
        }

        await fulfillment(of: [failureApplied], timeout: 5)
        await waitForCompletion(of: session)

        XCTAssertTrue(analyzer.wasDetachedBeforeRefresh)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
    }

    func testCompletedSessionIsReleasedWhileEngineRemainsAlive() async {
        let (eventStream, continuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let analyzer = MockStreamAnalyzer { eventStream }
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let readyApplied = expectation(description: "ready applied")
        var session: SafeMediaStreamSession? = await engine.start(
            policy: .adultMinimal
        ) { event in
            if event == .ready {
                readyApplied.fulfill()
            }
        }
        let sessionReference = WeakReference(session)

        await fulfillment(of: [readyApplied], timeout: 5)
        continuation.finish()
        await waitForCompletion(of: session)
        session = nil

        XCTAssertNil(sessionReference.value)
        withExtendedLifetime(engine) {}
    }

    func testFinishedSessionReleasesItsHandlerCaptureWithoutExplicitWait() async {
        let (eventStream, continuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let analyzer = MockStreamAnalyzer { eventStream }
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let readyApplied = expectation(description: "session ready")
        let captureReleased = expectation(description: "handler capture released")
        var capture: HandlerCapture? = HandlerCapture {
            captureReleased.fulfill()
        }
        let captureReference = WeakReference(capture)

        let session = await engine.start(policy: .adultMinimal) { [capture] event in
            _ = capture
            if event == .ready {
                readyApplied.fulfill()
            }
        }
        capture = nil
        await fulfillment(of: [readyApplied], timeout: 5)
        XCTAssertNotNil(captureReference.value)
        continuation.finish()
        await fulfillment(of: [captureReleased], timeout: 5)

        XCTAssertNil(captureReference.value)
        withExtendedLifetime(engine) {}
        withExtendedLifetime(session) {}
    }

    func testManualContinueOnlyResumesAnActiveBlurredStream() async {
        let (eventStream, continuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let analyzer = MockStreamAnalyzer { eventStream }
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let readyApplied = expectation(description: "ready applied")
        let blurApplied = expectation(description: "blur applied")

        let session = await engine.start(policy: .teenMessaging) { event in
            if event == .ready {
                readyApplied.fulfill()
            }
            if case .decision(let decision) = event,
               decision.action == .blurWithReveal {
                blurApplied.fulfill()
            }
        }

        await fulfillment(of: [readyApplied], timeout: 5)
        continuation.yield(.mockSensitiveVideo)
        await fulfillment(of: [blurApplied], timeout: 5)
        XCTAssertEqual(analyzer.continueStreamCallCount, 0)

        session.continueStream()
        XCTAssertEqual(analyzer.continueStreamCallCount, 1)

        await cancelAndWait(session)
        session.continueStream()
        XCTAssertEqual(analyzer.continueStreamCallCount, 1)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
    }

    func testStrictMidStreamFailureBlocksWithoutResuming() async {
        let (eventStream, continuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let analyzer = MockStreamAnalyzer { eventStream }
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let readyApplied = expectation(description: "ready applied")
        let failureApplied = expectation(description: "failure applied")
        var failureDecision: SafeMediaDecision?

        let session = await engine.start(policy: .childStrict) { event in
            if event == .ready {
                readyApplied.fulfill()
            }
            if case .decision(let decision) = event {
                failureDecision = decision
                failureApplied.fulfill()
            }
        }

        await fulfillment(of: [readyApplied], timeout: 5)
        continuation.finish(throwing: SafeMediaError.analysisFailed("forced"))
        await fulfillment(of: [failureApplied], timeout: 5)
        await waitForCompletion(of: session)

        XCTAssertEqual(failureDecision?.reason, .analysisFailed)
        XCTAssertEqual(failureDecision?.action, .block)
        XCTAssertEqual(analyzer.continueStreamCallCount, 0)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
    }

    func testThreeOverlappingStartsSuppressSupersededStartup() async {
        let gateEntered = expectation(description: "availability gate entered")
        let gate = MainActorGate {
            gateEntered.fulfill()
        }
        let analyzer = SuspendedAvailabilityAnalyzer(gate: gate)
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let thirdReady = expectation(description: "third session ready")
        var firstEvents: [SafeMediaStreamEvent] = []
        var secondEvents: [SafeMediaStreamEvent] = []
        var thirdEvents: [SafeMediaStreamEvent] = []

        let firstSession = await engine.start(policy: .adultMinimal) { event in
            firstEvents.append(event)
        }
        await fulfillment(of: [gateEntered], timeout: 5)

        let secondSession = await engine.start(policy: .adultMinimal) { event in
            secondEvents.append(event)
        }
        let thirdSession = await engine.start(policy: .adultMinimal) { event in
            thirdEvents.append(event)
            if event == .ready {
                thirdReady.fulfill()
            }
        }

        XCTAssertEqual(firstEvents, [.preparing])
        XCTAssertEqual(secondEvents, [.preparing])
        XCTAssertEqual(thirdEvents, [.preparing])

        gate.open()
        await fulfillment(of: [thirdReady], timeout: 5)
        await waitForCompletion(of: firstSession)
        await waitForCompletion(of: secondSession)

        XCTAssertEqual(firstEvents, [.preparing])
        XCTAssertEqual(secondEvents, [.preparing])
        XCTAssertEqual(thirdEvents, [.preparing, .ready])
        XCTAssertEqual(analyzer.availabilityCallCount, 2)
        XCTAssertEqual(analyzer.startAnalysisCallCount, 1)

        await cancelAndWait(thirdSession)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 1)
    }

    func testLateAttachmentAfterReplacementIsEndedAgain() async {
        let gateEntered = expectation(description: "attachment gate entered")
        let gate = MainActorGate {
            gateEntered.fulfill()
        }
        let analyzer = LateAttachingStreamAnalyzer(gate: gate)
        let engine = SafeMediaStreamEngine(analyzer: analyzer)
        let replacementReady = expectation(description: "replacement ready")
        var firstEvents: [SafeMediaStreamEvent] = []
        var replacementEvents: [SafeMediaStreamEvent] = []

        let firstSession = await engine.start(policy: .adultMinimal) { event in
            firstEvents.append(event)
        }
        await fulfillment(of: [gateEntered], timeout: 5)

        let replacementSession = await engine.start(
            policy: .adultMinimal
        ) { event in
            replacementEvents.append(event)
            if event == .ready {
                replacementReady.fulfill()
            }
        }

        gate.open()
        await fulfillment(of: [replacementReady], timeout: 5)
        await waitForCompletion(of: firstSession)

        XCTAssertEqual(firstEvents, [.preparing])
        XCTAssertEqual(replacementEvents, [.preparing, .ready])
        XCTAssertEqual(analyzer.startAnalysisCallCount, 2)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 2)
        XCTAssertEqual(analyzer.maximumAttachedStreamCount, 1)
        XCTAssertTrue(analyzer.isAttached)

        await cancelAndWait(replacementSession)
        XCTAssertEqual(analyzer.endAnalysisCallCount, 3)
        XCTAssertFalse(analyzer.isAttached)
    }

    func testResourcesReleaseAfterCancellation() async {
        let (eventStream, continuation) = MockStreamAnalyzer.EventStream
            .makeStream(bufferingPolicy: .unbounded)
        let upstreamTerminated = expectation(description: "upstream terminated")
        continuation.onTermination = { @Sendable _ in
            upstreamTerminated.fulfill()
        }
        var analyzer: MockStreamAnalyzer? = MockStreamAnalyzer { eventStream }
        let analyzerReference = WeakReference(analyzer)
        var engine: SafeMediaStreamEngine? = analyzer.map(SafeMediaStreamEngine.init)
        let readyApplied = expectation(description: "ready applied")
        var session = await engine?.start(policy: .adultMinimal) { event in
            if event == .ready {
                readyApplied.fulfill()
            }
        }

        await fulfillment(of: [readyApplied], timeout: 5)
        await cancelAndWait(session)
        await fulfillment(of: [upstreamTerminated], timeout: 5)
        session = nil
        engine = nil
        analyzer = nil

        XCTAssertNil(analyzerReference.value)
    }

    private func waitForCompletion(
        of session: SafeMediaStreamSession,
        timeout: TimeInterval = 5
    ) async {
        let completed = expectation(description: "session monitoring completed")
        let waiter = Task { @MainActor in
            await session.waitForCompletion()
            completed.fulfill()
        }

        let result = await XCTWaiter.fulfillment(
            of: [completed],
            timeout: timeout
        )
        guard result == .completed else {
            session.cancel()
            waiter.cancel()
            XCTFail("Timed out waiting for stream-session completion")
            return
        }

        waiter.cancel()
    }

    private func waitForCompletion(
        of session: SafeMediaStreamSession?,
        timeout: TimeInterval = 5
    ) async {
        guard let session else {
            return XCTFail("Expected a stream session")
        }
        await waitForCompletion(of: session, timeout: timeout)
    }

    private func cancelAndWait(
        _ session: SafeMediaStreamSession,
        timeout: TimeInterval = 5
    ) async {
        session.cancel()
        await waitForCompletion(of: session, timeout: timeout)
    }

    private func cancelAndWait(
        _ session: SafeMediaStreamSession?,
        timeout: TimeInterval = 5
    ) async {
        guard let session else {
            return XCTFail("Expected a stream session")
        }
        await cancelAndWait(session, timeout: timeout)
    }
}

@MainActor
private final class StreamSessionHolder {
    var session: SafeMediaStreamSession?
}

@MainActor
private final class HandlerCapture {
    private let onDeinit: @MainActor () -> Void

    init(onDeinit: @escaping @MainActor () -> Void) {
        self.onDeinit = onDeinit
    }

    isolated deinit {
        onDeinit()
    }
}

@MainActor
private final class ReplacementTraceAnalyzer: SafeMediaStreamAnalyzing {
    enum Step: Equatable {
        case concealed
        case analysisEnded
    }

    let base: MockStreamAnalyzer
    var trace: [Step] = []

    init(base: MockStreamAnalyzer) {
        self.base = base
    }

    func availability() async -> SafeMediaAvailability {
        await base.availability()
    }

    func startAnalysis() async throws
        -> AsyncThrowingStream<SafeMediaVerdict, any Error> {
        try await base.startAnalysis()
    }

    func continueStream() {
        base.continueStream()
    }

    func endAnalysis() {
        trace.append(.analysisEnded)
        base.endAnalysis()
    }
}

@MainActor
private final class PartiallyAttachingFailureAnalyzer: SafeMediaStreamAnalyzing {
    private var availabilityCallCount = 0
    private var isAttached = false

    private(set) var wasDetachedBeforeRefresh = false
    private(set) var endAnalysisCallCount = 0

    func availability() async -> SafeMediaAvailability {
        availabilityCallCount += 1
        if availabilityCallCount == 2 {
            wasDetachedBeforeRefresh = !isAttached
        }
        return .available
    }

    func startAnalysis() async throws
        -> AsyncThrowingStream<SafeMediaVerdict, any Error> {
        isAttached = true
        throw SafeMediaError.analysisFailed("partial attachment")
    }

    func continueStream() {}

    func endAnalysis() {
        endAnalysisCallCount += 1
        isAttached = false
    }
}

@MainActor
private final class WeakReference<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

@MainActor
private final class MainActorGate {
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

@MainActor
private final class SuspendedAvailabilityAnalyzer: SafeMediaStreamAnalyzing {
    private let gate: MainActorGate
    private var continuation:
        AsyncThrowingStream<SafeMediaVerdict, any Error>.Continuation?

    private(set) var availabilityCallCount = 0
    private(set) var startAnalysisCallCount = 0
    private(set) var endAnalysisCallCount = 0

    init(gate: MainActorGate) {
        self.gate = gate
    }

    func availability() async -> SafeMediaAvailability {
        availabilityCallCount += 1
        if availabilityCallCount == 1 {
            await gate.wait()
        }
        return .available
    }

    func startAnalysis() async throws
        -> AsyncThrowingStream<SafeMediaVerdict, any Error> {
        startAnalysisCallCount += 1
        let (stream, continuation) = AsyncThrowingStream<
            SafeMediaVerdict,
            any Error
        >.makeStream(bufferingPolicy: .unbounded)
        self.continuation = continuation
        return stream
    }

    func continueStream() {}

    func endAnalysis() {
        endAnalysisCallCount += 1
        continuation?.finish()
        continuation = nil
    }
}

@MainActor
private final class LateAttachingStreamAnalyzer: SafeMediaStreamAnalyzing {
    private let gate: MainActorGate
    private var continuation:
        AsyncThrowingStream<SafeMediaVerdict, any Error>.Continuation?
    private var attachedStreamCount = 0

    private(set) var startAnalysisCallCount = 0
    private(set) var endAnalysisCallCount = 0
    private(set) var maximumAttachedStreamCount = 0

    var isAttached: Bool {
        attachedStreamCount > 0
    }

    init(gate: MainActorGate) {
        self.gate = gate
    }

    func startAnalysis() async throws
        -> AsyncThrowingStream<SafeMediaVerdict, any Error> {
        startAnalysisCallCount += 1
        if startAnalysisCallCount == 1 {
            // Deliberately ignore task cancellation to model a faulty or slow
            // third-party conformer that attaches after an earlier end call.
            await gate.wait()
        }

        attachedStreamCount += 1
        maximumAttachedStreamCount = max(
            maximumAttachedStreamCount,
            attachedStreamCount
        )

        let (stream, continuation) = AsyncThrowingStream<
            SafeMediaVerdict,
            any Error
        >.makeStream(bufferingPolicy: .unbounded)
        self.continuation = continuation
        return stream
    }

    func continueStream() {}

    func endAnalysis() {
        endAnalysisCallCount += 1
        if attachedStreamCount > 0 {
            attachedStreamCount -= 1
        }
        continuation?.finish()
        continuation = nil
    }
}

@MainActor
private final class UngatedStreamAnalyzer: SafeMediaStreamAnalyzing {
    private let stream: AsyncThrowingStream<SafeMediaVerdict, any Error>
    private let continuation:
        AsyncThrowingStream<SafeMediaVerdict, any Error>.Continuation

    private(set) var continueStreamCallCount = 0
    private(set) var endAnalysisCallCount = 0

    init(
        stream: AsyncThrowingStream<SafeMediaVerdict, any Error>,
        continuation: AsyncThrowingStream<SafeMediaVerdict, any Error>.Continuation
    ) {
        self.stream = stream
        self.continuation = continuation
    }

    func startAnalysis() async throws
        -> AsyncThrowingStream<SafeMediaVerdict, any Error> {
        stream
    }

    func continueStream() {
        continueStreamCallCount += 1
    }

    func endAnalysis() {
        endAnalysisCallCount += 1
        continuation.finish()
    }
}

@MainActor
private final class AvailabilityRaceStreamAnalyzer: SafeMediaStreamAnalyzing {
    private(set) var availabilityCallCount = 0

    func availability() async -> SafeMediaAvailability {
        availabilityCallCount += 1
        return availabilityCallCount == 1
            ? .available
            : .unavailable(.analysisPolicyDisabled)
    }

    func startAnalysis() async throws
        -> AsyncThrowingStream<SafeMediaVerdict, any Error> {
        throw SafeMediaError.analysisFailed("policy changed")
    }

    func continueStream() {}
    func endAnalysis() {}
}
