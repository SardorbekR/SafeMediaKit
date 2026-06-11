import SafeMediaKit

/// Test analyzer returning forced results.
///
/// `analyze(_:)` ignores `availabilityResult` by design: `SafeMediaEngine`
/// consults `availability()` as a preflight and never calls `analyze` when it
/// reports unavailable. Calling `analyze` directly bypasses that preflight.
///
/// @unchecked: `Result<_, any Error>` holds a non-Sendable existential (the
/// PRD-specified shape). Safe in practice — value-type copies; only sharing a
/// mutable non-Sendable error instance across threads could race.
public struct MockSafeMediaAnalyzer: SafeMediaAnalyzing, @unchecked Sendable {
    public var result: Result<SafeMediaVerdict, any Error>
    public var availabilityResult: SafeMediaAvailability

    public init(
        result: Result<SafeMediaVerdict, any Error>,
        availability: SafeMediaAvailability = .available
    ) {
        self.result = result
        self.availabilityResult = availability
    }

    public func availability() async -> SafeMediaAvailability {
        availabilityResult
    }

    public func analyze(_ source: SafeMediaSource) async throws -> SafeMediaVerdict {
        try result.get()
    }
}
