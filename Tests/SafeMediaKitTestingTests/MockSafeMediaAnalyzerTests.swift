import SafeMediaKit
import SafeMediaKitTesting
import XCTest

final class MockSafeMediaAnalyzerTests: XCTestCase {
    func testReturnsForcedResult() async throws {
        let analyzer = MockSafeMediaAnalyzer(result: .success(.mockSensitive))

        let verdict = try await analyzer.analyze(
            .imageFile(URL(fileURLWithPath: "/tmp/mock.png"))
        )

        XCTAssertEqual(verdict, .mockSensitive)
    }

    func testReturnsForcedAvailability() async {
        let analyzer = MockSafeMediaAnalyzer(
            result: .success(.mockSafe),
            availability: .unavailable(.analysisPolicyDisabled)
        )

        let availability = await analyzer.availability()

        XCTAssertEqual(availability, .unavailable(.analysisPolicyDisabled))
    }

    func testThrowsForcedError() async {
        let analyzer = MockSafeMediaAnalyzer(
            result: .failure(SafeMediaError.analysisFailed("forced"))
        )

        do {
            _ = try await analyzer.analyze(
                .imageFile(URL(fileURLWithPath: "/tmp/mock.png"))
            )
            XCTFail("Expected analyzer to throw")
        } catch {
            XCTAssertTrue(error is SafeMediaError)
        }
    }
}
