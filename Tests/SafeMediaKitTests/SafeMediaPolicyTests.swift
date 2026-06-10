import SafeMediaKit
import XCTest

final class SafeMediaPolicyTests: XCTestCase {
    func testAdultMinimalPreset() {
        let policy = SafeMediaPolicy.adultMinimal

        XCTAssertEqual(policy.sensitiveAction, .blurWithReveal)
        XCTAssertEqual(policy.unknownAction, .allow)
        XCTAssertEqual(policy.unavailableAction, .allow)
        XCTAssertEqual(policy.failureAction, .allow)
        XCTAssertTrue(policy.allowReveal)
        XCTAssertFalse(policy.allowReport)
    }

    func testTeenMessagingPreset() {
        let policy = SafeMediaPolicy.teenMessaging

        XCTAssertEqual(policy.sensitiveAction, .blurWithReveal)
        XCTAssertEqual(policy.unknownAction, .blurWithReveal)
        XCTAssertEqual(policy.unavailableAction, .blurWithReveal)
        XCTAssertEqual(policy.failureAction, .blurWithReveal)
        XCTAssertTrue(policy.allowReveal)
        XCTAssertTrue(policy.allowReport)
    }

    func testChildStrictPresetBlocksSensitiveContent() {
        let policy = SafeMediaPolicy.childStrict

        XCTAssertEqual(policy.sensitiveAction, .block)
        XCTAssertEqual(policy.unknownAction, .block)
        XCTAssertEqual(policy.unavailableAction, .block)
        XCTAssertEqual(policy.failureAction, .block)
        XCTAssertFalse(policy.allowReveal)
        XCTAssertTrue(policy.allowReport)
    }

    func testClassroomStrictPresetBlocksSensitiveContent() {
        let policy = SafeMediaPolicy.classroomStrict

        XCTAssertEqual(policy.sensitiveAction, .block)
        XCTAssertEqual(policy.unknownAction, .block)
        XCTAssertEqual(policy.unavailableAction, .block)
        XCTAssertEqual(policy.failureAction, .block)
        XCTAssertFalse(policy.allowReveal)
        XCTAssertTrue(policy.allowReport)
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
    }
}
