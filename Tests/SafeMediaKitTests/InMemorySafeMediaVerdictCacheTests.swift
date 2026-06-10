import SafeMediaKit
import SafeMediaKitTesting
import XCTest

final class InMemorySafeMediaVerdictCacheTests: XCTestCase {
    func testStoresAndReturnsVerdict() async {
        let cache = InMemorySafeMediaVerdictCache()
        let key = SafeMediaCacheKey(rawValue: "cache-key")

        await cache.store(.mockSensitive, for: key)

        let verdict = await cache.verdict(for: key)
        XCTAssertEqual(verdict, .mockSensitive)
    }

    func testRemoveAllClearsVerdicts() async {
        let cache = InMemorySafeMediaVerdictCache()
        let key = SafeMediaCacheKey(rawValue: "cache-key")

        await cache.store(.mockSafe, for: key)
        await cache.removeAll()

        let verdict = await cache.verdict(for: key)
        XCTAssertNil(verdict)
    }
}
