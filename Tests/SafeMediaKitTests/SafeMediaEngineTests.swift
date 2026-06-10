import SafeMediaKit
import SafeMediaKitTesting
import XCTest

final class SafeMediaEngineTests: XCTestCase {
    func testSafeVerdictMapsToAllow() async {
        let analyzer = MockSafeMediaAnalyzer(result: .success(.mockSafe))
        let engine = SafeMediaEngine(analyzer: analyzer)

        let decision = await engine.evaluate(
            .imageFile(URL(fileURLWithPath: "/tmp/safe.png")),
            context: .incomingMessage,
            policy: .teenMessaging
        )

        XCTAssertEqual(decision.action, .allow)
        XCTAssertEqual(decision.reason, .safe)
    }

    func testSensitiveVerdictUsesPolicySensitiveAction() async {
        let policy = SafeMediaPolicy(
            sensitiveAction: .block,
            unknownAction: .allow,
            unavailableAction: .allow,
            failureAction: .allow,
            allowReveal: false,
            allowReport: true
        )
        let analyzer = MockSafeMediaAnalyzer(result: .success(.mockSensitive))
        let engine = SafeMediaEngine(analyzer: analyzer)

        let decision = await engine.evaluate(
            .imageFile(URL(fileURLWithPath: "/tmp/sensitive.png")),
            context: .incomingMessage,
            policy: policy
        )

        XCTAssertEqual(decision.action, .block)
        XCTAssertEqual(decision.reason, .sensitiveDetected)
    }

    func testUnknownAvailableVerdictUsesPolicyUnknownAction() async {
        let verdict = SafeMediaVerdict(
            sensitivity: .unknown,
            contentTypes: [],
            guidance: .none,
            availability: .available
        )
        let policy = SafeMediaPolicy(
            sensitiveAction: .allow,
            unknownAction: .block,
            unavailableAction: .allow,
            failureAction: .allow,
            allowReveal: false,
            allowReport: false
        )
        let analyzer = MockSafeMediaAnalyzer(result: .success(verdict))
        let engine = SafeMediaEngine(analyzer: analyzer)

        let decision = await engine.evaluate(
            .imageFile(URL(fileURLWithPath: "/tmp/unknown.png")),
            context: .incomingMessage,
            policy: policy
        )

        XCTAssertEqual(decision.action, .block)
        XCTAssertEqual(decision.reason, .unknownByPolicy)
    }

    func testUnavailableAvailabilityUsesPolicyUnavailableAction() async {
        let analyzer = MockSafeMediaAnalyzer(
            result: .success(.mockSafe),
            availability: .unavailable(.analysisPolicyDisabled)
        )
        let engine = SafeMediaEngine(analyzer: analyzer)

        let decision = await engine.evaluate(
            .imageFile(URL(fileURLWithPath: "/tmp/unavailable.png")),
            context: .incomingMessage,
            policy: .childStrict
        )

        XCTAssertEqual(decision.action, .block)
        XCTAssertEqual(decision.reason, .unavailableByPolicy)
        XCTAssertEqual(decision.verdict.availability, .unavailable(.analysisPolicyDisabled))
    }

    func testAnalyzerErrorsUsePolicyFailureAction() async {
        let analyzer = MockSafeMediaAnalyzer(
            result: .failure(SafeMediaError.analysisFailed("forced"))
        )
        let policy = SafeMediaPolicy(
            sensitiveAction: .allow,
            unknownAction: .allow,
            unavailableAction: .allow,
            failureAction: .block,
            allowReveal: false,
            allowReport: true
        )
        let engine = SafeMediaEngine(analyzer: analyzer)

        let decision = await engine.evaluate(
            .imageFile(URL(fileURLWithPath: "/tmp/error.png")),
            context: .incomingMessage,
            policy: policy
        )

        XCTAssertEqual(decision.action, .block)
        XCTAssertEqual(decision.reason, .analysisFailed)
    }

    func testCacheIsUsedForRepeatedAvailableResults() async {
        let analyzer = AnalyzerProbe(result: .success(.mockSensitive))
        let cache = InMemorySafeMediaVerdictCache()
        let engine = SafeMediaEngine(analyzer: analyzer, cache: cache)
        let key = SafeMediaCacheKey(rawValue: "message-1")

        _ = await engine.evaluate(
            .imageFile(URL(fileURLWithPath: "/tmp/cached.png")),
            context: .incomingMessage,
            policy: .teenMessaging,
            cacheKey: key
        )
        _ = await engine.evaluate(
            .imageFile(URL(fileURLWithPath: "/tmp/cached.png")),
            context: .incomingMessage,
            policy: .teenMessaging,
            cacheKey: key
        )

        let counts = await analyzer.counts()
        XCTAssertEqual(counts.analyze, 1)
        XCTAssertEqual(counts.availability, 2)
    }

    func testUnavailableVerdictsAreNotCached() async {
        let analyzer = AnalyzerProbe(result: .success(.mockUnknownUnavailable))
        let cache = InMemorySafeMediaVerdictCache()
        let engine = SafeMediaEngine(analyzer: analyzer, cache: cache)
        let key = SafeMediaCacheKey(rawValue: "message-2")

        _ = await engine.evaluate(
            .imageFile(URL(fileURLWithPath: "/tmp/not-cached.png")),
            context: .incomingMessage,
            policy: .teenMessaging,
            cacheKey: key
        )
        _ = await engine.evaluate(
            .imageFile(URL(fileURLWithPath: "/tmp/not-cached.png")),
            context: .incomingMessage,
            policy: .teenMessaging,
            cacheKey: key
        )

        let counts = await analyzer.counts()
        XCTAssertEqual(counts.analyze, 2)
    }

    func testAnalyzerFailuresAreNotCached() async {
        let analyzer = AnalyzerProbe(result: .failure(.analysisFailed("forced")))
        let cache = InMemorySafeMediaVerdictCache()
        let engine = SafeMediaEngine(analyzer: analyzer, cache: cache)
        let key = SafeMediaCacheKey(rawValue: "message-3")

        _ = await engine.evaluate(
            .imageFile(URL(fileURLWithPath: "/tmp/failure.png")),
            context: .incomingMessage,
            policy: .teenMessaging,
            cacheKey: key
        )
        _ = await engine.evaluate(
            .imageFile(URL(fileURLWithPath: "/tmp/failure.png")),
            context: .incomingMessage,
            policy: .teenMessaging,
            cacheKey: key
        )

        let counts = await analyzer.counts()
        XCTAssertEqual(counts.analyze, 2)
    }

    func testAvailabilityIsCheckedBeforeCacheLookup() async {
        let key = SafeMediaCacheKey(rawValue: "message-4")
        let cache = InMemorySafeMediaVerdictCache(verdicts: [key: .mockSafe])
        let analyzer = AnalyzerProbe(
            result: .success(.mockSafe),
            availability: .unavailable(.analysisPolicyDisabled)
        )
        let engine = SafeMediaEngine(analyzer: analyzer, cache: cache)

        let decision = await engine.evaluate(
            .imageFile(URL(fileURLWithPath: "/tmp/preflight.png")),
            context: .incomingMessage,
            policy: .childStrict,
            cacheKey: key
        )

        let counts = await analyzer.counts()
        XCTAssertEqual(decision.reason, .unavailableByPolicy)
        XCTAssertEqual(decision.action, .block)
        XCTAssertEqual(counts.analyze, 0)
        XCTAssertEqual(counts.availability, 1)
    }
}

private actor AnalyzerProbe: SafeMediaAnalyzing {
    private let result: Result<SafeMediaVerdict, SafeMediaError>
    private let availabilityResult: SafeMediaAvailability
    private var analyzeCount = 0
    private var availabilityCount = 0

    init(
        result: Result<SafeMediaVerdict, SafeMediaError>,
        availability: SafeMediaAvailability = .available
    ) {
        self.result = result
        self.availabilityResult = availability
    }

    func availability() async -> SafeMediaAvailability {
        availabilityCount += 1
        return availabilityResult
    }

    func analyze(_ source: SafeMediaSource) async throws -> SafeMediaVerdict {
        analyzeCount += 1
        return try result.get()
    }

    func counts() -> (availability: Int, analyze: Int) {
        (availabilityCount, analyzeCount)
    }
}
