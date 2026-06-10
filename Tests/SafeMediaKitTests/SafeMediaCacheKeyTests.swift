import SafeMediaKit
import XCTest

final class SafeMediaCacheKeyTests: XCTestCase {
    func testFileURLCacheKeyChangesWhenFileMetadataChanges() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fileURL = directory.appendingPathComponent("image.dat")
        try Data([0, 1, 2]).write(to: fileURL)
        let firstKey = SafeMediaCacheKeyFactory.fileURL(fileURL)

        try Data([0, 1, 2, 3]).write(to: fileURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 4_100_000_000)],
            ofItemAtPath: fileURL.path
        )
        let secondKey = SafeMediaCacheKeyFactory.fileURL(fileURL)

        XCTAssertNotEqual(firstKey, secondKey)
    }

    func testRawCacheKeysAreHashable() {
        let first = SafeMediaCacheKey(rawValue: "a")
        let second = SafeMediaCacheKey(rawValue: "a")

        XCTAssertEqual(first, second)
        XCTAssertEqual(Set([first, second]).count, 1)
    }
}
