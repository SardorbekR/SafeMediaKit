import SafeMediaKit

public struct MockSafeMediaAnalyzer: SafeMediaAnalyzing {
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
