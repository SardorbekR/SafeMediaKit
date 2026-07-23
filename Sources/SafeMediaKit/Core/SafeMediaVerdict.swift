/// A category of sensitive content reported by an analyzer.
public enum SafeMediaContentType: Sendable, Hashable {
    /// Nudity reported without a more specific content category.
    case nudity

    /// Sexually explicit content.
    case sexuallyExplicit

    /// Gore or violent content.
    case goreOrViolence

    /// Sensitive content whose category isn't known.
    case unknownSensitive
}

/// The analyzer's overall classification of a media item.
public enum SafeMediaSensitivity: Sendable, Hashable {
    /// The analyzer didn't flag the media as sensitive.
    case safe

    /// The analyzer detected sensitive content.
    case sensitive

    /// The analyzer couldn't determine whether the media is sensitive.
    case unknown
}

/// Analyzer guidance for presenting or interrupting media.
public struct SafeMediaGuidance: Sendable, Hashable {
    /// Whether the interface should indicate that the media may be sensitive.
    public var shouldIndicateSensitivity: Bool

    /// Whether video playback should be interrupted.
    public var shouldInterruptVideo: Bool

    /// Whether audio should be muted.
    public var shouldMuteAudio: Bool

    /// Creates a set of presentation and playback recommendations.
    public init(
        shouldIndicateSensitivity: Bool,
        shouldInterruptVideo: Bool,
        shouldMuteAudio: Bool
    ) {
        self.shouldIndicateSensitivity = shouldIndicateSensitivity
        self.shouldInterruptVideo = shouldInterruptVideo
        self.shouldMuteAudio = shouldMuteAudio
    }
}

public extension SafeMediaGuidance {
    /// Guidance with every recommendation disabled.
    static let none = SafeMediaGuidance(
        shouldIndicateSensitivity: false,
        shouldInterruptVideo: false,
        shouldMuteAudio: false
    )
}

/// A media-sensitivity classification and associated presentation guidance.
public struct SafeMediaVerdict: Sendable, Hashable {
    /// The overall sensitivity classification.
    public let sensitivity: SafeMediaSensitivity

    /// The sensitive categories associated with the verdict.
    public let contentTypes: Set<SafeMediaContentType>

    /// Recommendations returned with the classification.
    public let guidance: SafeMediaGuidance

    /// The availability associated with the verdict.
    public let availability: SafeMediaAvailability

    /// Creates a verdict from its classification, categories, guidance, and
    /// availability.
    public init(
        sensitivity: SafeMediaSensitivity,
        contentTypes: Set<SafeMediaContentType>,
        guidance: SafeMediaGuidance,
        availability: SafeMediaAvailability
    ) {
        self.sensitivity = sensitivity
        self.contentTypes = contentTypes
        self.guidance = guidance
        self.availability = availability
    }
}
