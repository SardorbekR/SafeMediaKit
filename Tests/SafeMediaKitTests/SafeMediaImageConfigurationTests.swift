#if canImport(SwiftUI)
import SafeMediaKit
import XCTest

final class SafeMediaImageConfigurationTests: XCTestCase {
    func testConfigurationClampsNegativeBlurRadius() {
        let configuration = SafeMediaImageConfiguration(blurRadius: -8)

        XCTAssertEqual(configuration.blurRadius, 0)
    }
}
#endif
