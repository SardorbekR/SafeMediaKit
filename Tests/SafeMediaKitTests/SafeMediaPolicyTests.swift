import SafeMediaKit
import XCTest

final class SafeMediaPolicyTests: XCTestCase {
    func testAdultMinimalPreset() {
        let policy = SafeMediaPolicy.adultMinimal

        XCTAssertEqual(policy.sensitiveAction, .blurWithReveal)
        XCTAssertEqual(policy.unknownAction, .allow)
        XCTAssertEqual(policy.unavailableAction, .allow)
        XCTAssertEqual(policy.failureAction, .allow)
        XCTAssertEqual(policy.streamSensitiveAction, .allow)
        XCTAssertTrue(policy.allowReveal)
        XCTAssertFalse(policy.allowReport)
    }

    func testTeenMessagingPreset() {
        let policy = SafeMediaPolicy.teenMessaging

        XCTAssertEqual(policy.sensitiveAction, .blurWithReveal)
        XCTAssertEqual(policy.unknownAction, .blurWithReveal)
        XCTAssertEqual(policy.unavailableAction, .blurWithReveal)
        XCTAssertEqual(policy.failureAction, .blurWithReveal)
        XCTAssertEqual(policy.streamSensitiveAction, .blurWithReveal)
        XCTAssertTrue(policy.allowReveal)
        XCTAssertTrue(policy.allowReport)
    }

    func testChildStrictPresetBlocksSensitiveContent() {
        let policy = SafeMediaPolicy.childStrict

        XCTAssertEqual(policy.sensitiveAction, .block)
        XCTAssertEqual(policy.unknownAction, .block)
        XCTAssertEqual(policy.unavailableAction, .block)
        XCTAssertEqual(policy.failureAction, .block)
        XCTAssertEqual(policy.streamSensitiveAction, .interruptVideo)
        XCTAssertFalse(policy.allowReveal)
        XCTAssertTrue(policy.allowReport)
    }

    @available(*, deprecated)
    func testClassroomStrictIsAnAliasForChildStrict() {
        XCTAssertEqual(SafeMediaPolicy.classroomStrict, SafeMediaPolicy.childStrict)
    }

    func testPolicyClampsNegativeBlurRadius() {
        let policy = SafeMediaPolicy(
            sensitiveAction: .blur,
            unknownAction: .blur,
            unavailableAction: .blur,
            failureAction: .blur,
            allowReveal: false,
            allowReport: false,
            blurRadius: -4
        )

        XCTAssertEqual(policy.blurRadius, 0)
        XCTAssertNil(policy.streamSensitiveAction)
    }

    func testOriginalInitializerRemainsUsableAsFunctionValue() {
        typealias PolicyFactory = (
            SafeMediaAction,
            SafeMediaAction,
            SafeMediaAction,
            SafeMediaAction,
            Bool,
            Bool,
            Double
        ) -> SafeMediaPolicy
        let factory: PolicyFactory = SafeMediaPolicy.init

        let policy = factory(
            .block,
            .blur,
            .allow,
            .muteAudio,
            false,
            true,
            12
        )

        XCTAssertEqual(policy.sensitiveAction, .block)
        XCTAssertEqual(policy.unknownAction, .blur)
        XCTAssertEqual(policy.unavailableAction, .allow)
        XCTAssertEqual(policy.failureAction, .muteAudio)
        XCTAssertFalse(policy.allowReveal)
        XCTAssertTrue(policy.allowReport)
        XCTAssertNil(policy.streamSensitiveAction)
        XCTAssertEqual(policy.blurRadius, 12)
    }
}
