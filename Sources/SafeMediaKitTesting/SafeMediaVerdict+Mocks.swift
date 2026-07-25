import SafeMediaKit

/// Deterministic verdict fixtures for tests and previews.
public extension SafeMediaVerdict {
    /// An available verdict for media classified as safe.
    static let mockSafe = SafeMediaVerdict(
        sensitivity: .safe,
        contentTypes: [],
        guidance: .none,
        availability: .available
    )

    /// An available nudity verdict with sensitivity indication guidance.
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

    /// A sensitive live-video verdict with every Apple guidance flag enabled.
    static let mockSensitiveVideo = SafeMediaVerdict(
        sensitivity: .sensitive,
        contentTypes: [.nudity],
        guidance: SafeMediaGuidance(
            shouldIndicateSensitivity: true,
            shouldInterruptVideo: true,
            shouldMuteAudio: true
        ),
        availability: .available
    )

    /// An unknown verdict representing analysis disabled by policy.
    static let mockUnknownUnavailable = SafeMediaVerdict(
        sensitivity: .unknown,
        contentTypes: [],
        guidance: .none,
        availability: .unavailable(.analysisPolicyDisabled)
    )
}
