import SafeMediaKit

/// A configurable analyzer for tests and previews.
///
/// ``analyze(_:)`` ignores ``availabilityResult``. `SafeMediaEngine` checks
/// ``availability()`` before requesting analysis, while direct calls to
/// ``analyze(_:)`` bypass that preflight.
public struct MockSafeMediaAnalyzer: SafeMediaAnalyzing {
    /// The success value or error produced by ``analyze(_:)``.
    public var result: Result<SafeMediaVerdict, any Error>

    /// The value returned by ``availability()``.
    public var availabilityResult: SafeMediaAvailability

    /// Creates an analyzer with configurable analysis and availability
    /// responses.
    public init(
        result: Result<SafeMediaVerdict, any Error>,
        availability: SafeMediaAvailability = .available
    ) {
        self.result = result
        self.availabilityResult = availability
    }

    /// Returns the configured ``availabilityResult``.
    public func availability() async -> SafeMediaAvailability {
        availabilityResult
    }

    /// Returns the configured value or throws the configured error without
    /// inspecting the source.
    public func analyze(_ source: SafeMediaSource) async throws -> SafeMediaVerdict {
        try result.get()
    }
}
