public protocol SafeMediaAnalyzing: Sendable {
    func availability() async -> SafeMediaAvailability
    func analyze(_ source: SafeMediaSource) async throws -> SafeMediaVerdict
}

public extension SafeMediaAnalyzing {
    func availability() async -> SafeMediaAvailability {
        .available
    }
}
