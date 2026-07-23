/// An analyzer that reports its availability and evaluates local media.
public protocol SafeMediaAnalyzing: Sendable {
    /// Returns whether the analyzer can attempt analysis in the current
    /// environment.
    func availability() async -> SafeMediaAvailability

    /// Analyzes a media source and returns a verdict.
    func analyze(_ source: SafeMediaSource) async throws -> SafeMediaVerdict
}

public extension SafeMediaAnalyzing {
    /// Reports analysis as available for analyzers without a separate preflight.
    func availability() async -> SafeMediaAvailability {
        .available
    }
}
