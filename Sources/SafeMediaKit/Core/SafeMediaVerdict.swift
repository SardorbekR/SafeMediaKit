public enum SafeMediaContentType: Sendable, Hashable {
    case nudity
    case sexuallyExplicit
    case goreOrViolence
    case unknownSensitive
}

public enum SafeMediaSensitivity: Sendable, Hashable {
    case safe
    case sensitive
    case unknown
}

public struct SafeMediaGuidance: Sendable, Hashable {
    public var shouldIndicateSensitivity: Bool
    public var shouldInterruptVideo: Bool
    public var shouldMuteAudio: Bool

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
    static let none = SafeMediaGuidance(
        shouldIndicateSensitivity: false,
        shouldInterruptVideo: false,
        shouldMuteAudio: false
    )
}

public struct SafeMediaVerdict: Sendable, Hashable {
    public let sensitivity: SafeMediaSensitivity
    public let contentTypes: Set<SafeMediaContentType>
    public let guidance: SafeMediaGuidance
    public let availability: SafeMediaAvailability

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
