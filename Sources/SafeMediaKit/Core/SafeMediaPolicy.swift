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

    /// Interrupt the active video stream or its delivery.
    case interruptVideo

    /// Mute the current audio stream and leave the video visible.
    ///
    /// This is an audio-only intervention. Used as a live-video action, it
    /// resumes the analyzer's stream, which removes Apple's automatic video
    /// censorship. Choose `blur`, `blurWithReveal`, `block`, or
    /// `interruptVideo` when the video itself must stay concealed.
    case muteAudio
}

/// Rules for translating verdict states into intervention actions.
public struct SafeMediaPolicy: Sendable, Hashable {
    /// The action for sensitive finite media and the live-video fallback when
    /// ``streamSensitiveAction`` is `nil`.
    public var sensitiveAction: SafeMediaAction

    /// The action for media the analyzer can't classify.
    public var unknownAction: SafeMediaAction

    /// The action for a safe or unknown verdict when analysis can't be attempted.
    public var unavailableAction: SafeMediaAction

    /// The action when analysis or bundled-view media loading fails.
    public var failureAction: SafeMediaAction

    /// The action for sensitive content detected in a live video stream.
    ///
    /// ``SafeMediaStreamEngine`` uses this value. When `nil`, it falls back to
    /// ``sensitiveAction``. Finite ``SafeMediaEngine`` evaluation always uses
    /// `sensitiveAction`, even when its context is ``SafeMediaContext/liveVideo``.
    /// The built-in presets provide stream-specific values without changing
    /// their image and file-video behavior.
    ///
    /// `allow` and `muteAudio` resume the analyzer as soon as the handler
    /// returns, which removes Apple's automatic video censorship and makes the
    /// detected video visible again. Only `blur`, `blurWithReveal`, `block`,
    /// and `interruptVideo` keep the video concealed.
    public var streamSensitiveAction: SafeMediaAction?

    /// Whether a blur-with-reveal decision may expose a reveal control.
    public var allowReveal: Bool

    /// Whether bundled overlays may expose a report control.
    public var allowReport: Bool

    /// The blur radius for custom decision-rendering interfaces.
    public var blurRadius: Double

    /// Creates a finite-media policy for sensitive, unknown, unavailable, and
    /// failed states. Live video inherits `sensitiveAction`.
    ///
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
        self.init(
            sensitiveAction: sensitiveAction,
            unknownAction: unknownAction,
            unavailableAction: unavailableAction,
            failureAction: failureAction,
            allowReveal: allowReveal,
            allowReport: allowReport,
            blurRadius: blurRadius,
            streamSensitiveAction: nil
        )
    }

    /// Creates a policy with a distinct action for sensitive live video.
    ///
    /// Pass `nil` to inherit `sensitiveAction`. Negative initial blur radii are
    /// clamped to zero.
    public init(
        sensitiveAction: SafeMediaAction,
        unknownAction: SafeMediaAction,
        unavailableAction: SafeMediaAction,
        failureAction: SafeMediaAction,
        allowReveal: Bool,
        allowReport: Bool,
        blurRadius: Double = 18,
        streamSensitiveAction: SafeMediaAction?
    ) {
        self.sensitiveAction = sensitiveAction
        self.unknownAction = unknownAction
        self.unavailableAction = unavailableAction
        self.failureAction = failureAction
        self.streamSensitiveAction = streamSensitiveAction
        self.allowReveal = allowReveal
        self.allowReport = allowReport
        self.blurRadius = max(0, blurRadius)
    }
}

public extension SafeMediaPolicy {
    /// A permissive preset that blurs sensitive finite media with reveal and
    /// allows sensitive live video to proceed.
    static let adultMinimal = SafeMediaPolicy(
        sensitiveAction: .blurWithReveal,
        unknownAction: .allow,
        unavailableAction: .allow,
        failureAction: .allow,
        allowReveal: true,
        allowReport: false,
        streamSensitiveAction: .allow
    )

    /// A messaging preset that treats unknown, unavailable, and failed
    /// analysis cautiously.
    static let teenMessaging = SafeMediaPolicy(
        sensitiveAction: .blurWithReveal,
        unknownAction: .blurWithReveal,
        unavailableAction: .blurWithReveal,
        failureAction: .blurWithReveal,
        allowReveal: true,
        allowReport: true,
        streamSensitiveAction: .blurWithReveal
    )

    /// A strict preset for parent-managed child accounts and school-managed
    /// devices.
    ///
    /// Blocks sensitive finite media, interrupts sensitive live video, and
    /// blocks unknown, unavailable, and failed states. It offers no reveal.
    /// Both deployments want the same fail-closed interventions.
    static let childStrict = SafeMediaPolicy(
        sensitiveAction: .block,
        unknownAction: .block,
        unavailableAction: .block,
        failureAction: .block,
        allowReveal: false,
        allowReport: true,
        streamSensitiveAction: .interruptVideo
    )

    /// A deprecated alias for ``childStrict``.
    ///
    /// The two presets have always been identical in every field. Classroom
    /// deployment is expressed through ``SafeMediaContext/classroomSubmission``
    /// and host-app configuration, not through a separate policy.
    @available(
        *,
        deprecated,
        renamed: "childStrict",
        message: "Identical to childStrict in every field. Use childStrict for classroom deployments. Scheduled for removal no earlier than 1.0."
    )
    static let classroomStrict = childStrict
}
