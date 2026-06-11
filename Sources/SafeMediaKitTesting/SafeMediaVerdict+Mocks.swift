import SafeMediaKit

public extension SafeMediaVerdict {
    static let mockSafe = SafeMediaVerdict(
        sensitivity: .safe,
        contentTypes: [],
        guidance: .none,
        availability: .available
    )

    static let mockSensitive = SafeMediaVerdict(
        sensitivity: .sensitive,
        contentTypes: [.nudity],
        guidance: SafeMediaGuidance(
            shouldIndicateSensitivity: true,
            shouldInterruptVideo: false,
            shouldMuteAudio: false
        ),
        availability: .available
    )

    static let mockUnknownUnavailable = SafeMediaVerdict(
        sensitivity: .unknown,
        contentTypes: [],
        guidance: .none,
        availability: .unavailable(.analysisPolicyDisabled)
    )
}
