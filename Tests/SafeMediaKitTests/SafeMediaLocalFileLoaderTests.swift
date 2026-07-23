import Foundation
@testable import SafeMediaKit
import XCTest

final class SafeMediaLocalFileLoaderTests: XCTestCase {
    func testReadsLocalFile() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let expectedData = Data([0x01, 0x02, 0x03])
        try expectedData.write(to: fileURL)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let data = try await SafeMediaLocalFileLoader.readData(from: fileURL)

        XCTAssertEqual(data, expectedData)
    }

    func testRejectsNonFileURL() async throws {
        let nonFileURL = try XCTUnwrap(
            URL(string: "safemedia-test://example/image.png")
        )

        do {
            _ = try await SafeMediaLocalFileLoader.readData(from: nonFileURL)
            XCTFail("Expected a non-file URL to fail")
        } catch {
            XCTAssertEqual(error as? SafeMediaError, .imageLoadingFailed)
        }
    }
}
