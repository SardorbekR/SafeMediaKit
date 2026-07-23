/// An intervention a host app can apply after media evaluation.
public enum SafeMediaAction: Sendable, Hashable {
    /// Display the media normally.
    case allow

    /// Obscure the media without offering the bundled reveal action.
    case blur

    /// Obscure the media and permit a policy-gated reveal action.
    case blurWithReveal

    /// Hide the media instead of displaying its contents.
    case block

    /// Interrupt video playback.
    case interruptVideo

    /// Mute the current audio stream.
    case muteAudio
}

/// Rules for translating verdict states into intervention actions.
public struct SafeMediaPolicy: Sendable, Hashable {
    /// The action for media reported as sensitive.
    public var sensitiveAction: SafeMediaAction

    /// The action for media the analyzer can't classify.
    public var unknownAction: SafeMediaAction

    /// The action for a safe or unknown verdict when analysis can't be attempted.
    public var unavailableAction: SafeMediaAction

    /// The action when analysis or bundled-view media loading fails.
    public var failureAction: SafeMediaAction

    /// Whether a blur-with-reveal decision may expose a reveal control.
    public var allowReveal: Bool

    /// Whether bundled overlays may expose a report control.
    public var allowReport: Bool

    /// The blur radius for custom decision-rendering interfaces.
    public var blurRadius: Double

    /// Creates a policy for sensitive, unknown, unavailable, and failed states.
    /// Negative initial blur radii are clamped to zero.
    public init(
        sensitiveAction: SafeMediaAction,
        unknownAction: SafeMediaAction,
        unavailableAction: SafeMediaAction,
        failureAction: SafeMediaAction,
        allowReveal: Bool,
        allowReport: Bool,
        blurRadius: Double = 18
    ) {
        self.sensitiveAction = sensitiveAction
        self.unknownAction = unknownAction
        self.unavailableAction = unavailableAction
        self.failureAction = failureAction
        self.allowReveal = allowReveal
        self.allowReport = allowReport
        self.blurRadius = max(0, blurRadius)
    }
}

public extension SafeMediaPolicy {
    /// A permissive preset that intervenes only for known-sensitive media.
    static let adultMinimal = SafeMediaPolicy(
        sensitiveAction: .blurWithReveal,
        unknownAction: .allow,
        unavailableAction: .allow,
        failureAction: .allow,
        allowReveal: true,
        allowReport: false
    )

    /// A messaging preset that treats unknown, unavailable, and failed
    /// analysis cautiously.
    static let teenMessaging = SafeMediaPolicy(
        sensitiveAction: .blurWithReveal,
        unknownAction: .blurWithReveal,
        unavailableAction: .blurWithReveal,
        failureAction: .blurWithReveal,
        allowReveal: true,
        allowReport: true
    )

    /// A strict preset that blocks sensitive, unknown, unavailable, and failed
    /// analysis.
    static let childStrict = SafeMediaPolicy(
        sensitiveAction: .block,
        unknownAction: .block,
        unavailableAction: .block,
        failureAction: .block,
        allowReveal: false,
        allowReport: true
    )

    /// A strict classroom preset that blocks any result other than known-safe
    /// media.
    static let classroomStrict = SafeMediaPolicy(
        sensitiveAction: .block,
        unknownAction: .block,
        unavailableAction: .block,
        failureAction: .block,
        allowReveal: false,
        allowReport: true
    )
}
