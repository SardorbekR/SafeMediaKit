#if canImport(SwiftUI)
import SafeMediaKit
import XCTest

final class SafeMediaOverlayStateTests: XCTestCase {
    func testUnavailableReasonUsesUnavailableCopyRegardlessOfAction() {
        let state = makeState(
            action: .block,
            reason: .unavailableByPolicy,
            policy: .childStrict
        )

        XCTAssertEqual(state.title, SafeMediaImageConfiguration.default.unavailableTitle)
        XCTAssertEqual(state.message, SafeMediaImageConfiguration.default.unavailableMessage)
    }

    func testBlockActionUsesBlockedCopy() {
        let state = makeState(
            action: .block,
            reason: .sensitiveDetected,
            policy: .childStrict
        )

        XCTAssertEqual(state.title, SafeMediaImageConfiguration.default.blockedTitle)
        XCTAssertEqual(state.message, SafeMediaImageConfiguration.default.blockedMessage)
    }

    func testBlurWithRevealUsesWarningCopy() {
        let state = makeState(
            action: .blurWithReveal,
            reason: .sensitiveDetected,
            policy: .teenMessaging
        )

        XCTAssertEqual(state.title, SafeMediaImageConfiguration.default.warningTitle)
        XCTAssertEqual(state.message, SafeMediaImageConfiguration.default.warningMessage)
    }

    func testAnalysisFailedWithNonBlockActionUsesWarningCopy() {
        let state = makeState(
            action: .blurWithReveal,
            reason: .analysisFailed,
            policy: .teenMessaging
        )

        XCTAssertEqual(state.title, SafeMediaImageConfiguration.default.warningTitle)
    }

    func testCanRevealRequiresImageRevealActionAndPolicy() {
        XCTAssertTrue(
            makeState(action: .blurWithReveal, reason: .sensitiveDetected, policy: .teenMessaging).canReveal
        )
        XCTAssertFalse(
            makeState(
                action: .blurWithReveal,
                reason: .sensitiveDetected,
                policy: .teenMessaging,
                hasImage: false
            ).canReveal
        )
        XCTAssertFalse(
            makeState(action: .blur, reason: .sensitiveDetected, policy: .teenMessaging).canReveal
        )
        XCTAssertFalse(
            makeState(action: .block, reason: .sensitiveDetected, policy: .childStrict).canReveal
        )
        XCTAssertFalse(
            makeState(action: .blurWithReveal, reason: .sensitiveDetected, policy: .childStrict).canReveal
        )
    }

    func testCanReportRequiresConfigurationAndPolicy() {
        XCTAssertTrue(
            makeState(action: .blurWithReveal, reason: .sensitiveDetected, policy: .teenMessaging).canReport
        )
        XCTAssertFalse(
            makeState(action: .blurWithReveal, reason: .sensitiveDetected, policy: .adultMinimal).canReport
        )
        XCTAssertFalse(
            makeState(
                action: .blurWithReveal,
                reason: .sensitiveDetected,
                policy: .teenMessaging,
                configuration: SafeMediaImageConfiguration(showsReportButton: false)
            ).canReport
        )
    }

    @MainActor
    func testRevealIsNoOpWhenCanRevealIsFalse() {
        var revealCount = 0
        let state = makeState(
            action: .block,
            reason: .sensitiveDetected,
            policy: .childStrict,
            onReveal: { revealCount += 1 }
        )

        state.reveal()

        XCTAssertFalse(state.canReveal)
        XCTAssertEqual(revealCount, 0)
    }

    @MainActor
    func testRevealFiresOnceWhenAllowed() {
        var revealCount = 0
        let state = makeState(
            action: .blurWithReveal,
            reason: .sensitiveDetected,
            policy: .teenMessaging,
            onReveal: { revealCount += 1 }
        )

        state.reveal()

        XCTAssertTrue(state.canReveal)
        XCTAssertEqual(revealCount, 1)
    }

    @MainActor
    func testReportFiresRegardlessOfCanReport() {
        var reportCount = 0
        let state = makeState(
            action: .blurWithReveal,
            reason: .sensitiveDetected,
            policy: .adultMinimal,
            onReport: { reportCount += 1 }
        )

        state.report()

        XCTAssertFalse(state.canReport)
        XCTAssertEqual(reportCount, 1)
    }

    private func makeState(
        action: SafeMediaAction,
        reason: SafeMediaDecisionReason,
        policy: SafeMediaPolicy,
        hasImage: Bool = true,
        configuration: SafeMediaImageConfiguration = .default,
        onReveal: @escaping @MainActor @Sendable () -> Void = {},
        onReport: @escaping @MainActor @Sendable () -> Void = {}
    ) -> SafeMediaOverlayState {
        let decision = SafeMediaDecision(
            action: action,
            verdict: SafeMediaVerdict(
                sensitivity: .sensitive,
                contentTypes: [.nudity],
                guidance: .none,
                availability: .available
            ),
            context: .incomingMessage,
            policy: policy,
            reason: reason
        )
        return SafeMediaOverlayState(
            decision: decision,
            configuration: configuration,
            hasImage: hasImage,
            onReveal: onReveal,
            onReport: onReport
        )
    }
}
#endif
