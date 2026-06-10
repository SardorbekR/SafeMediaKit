import SafeMediaKit

public extension SafeMediaVerdict {
    static let mockSafe = SafeMediaVerdict(
        sensitivity: .safe,
        contentTypes: [],
        guidance: .none,
        availability: .available
    )

    // Mirrors what `AppleSensitiveContentAnalyzer` produces in MVP:
    // guidance stays `.none` until stream analyzers populate it.
    static let mockSensitive = SafeMediaVerdict(
        sensitivity: .sensitive,
        contentTypes: [.nudity],
        guidance: .none,
        availability: .available
    )

    static let mockUnknownUnavailable = SafeMediaVerdict(
        sensitivity: .unknown,
        contentTypes: [],
        guidance: .none,
        availability: .unavailable(.analysisPolicyDisabled)
    )
}
