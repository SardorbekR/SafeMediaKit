public enum SafeMediaAction: Sendable, Hashable {
    case allow
    case blur
    case blurWithReveal
    case block
    case interruptVideo
    case muteAudio
}

public struct SafeMediaPolicy: Sendable, Hashable {
    public var sensitiveAction: SafeMediaAction
    public var unknownAction: SafeMediaAction
    public var unavailableAction: SafeMediaAction
    public var failureAction: SafeMediaAction
    public var allowReveal: Bool
    public var allowReport: Bool
    public var blurRadius: Double

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
    static let adultMinimal = SafeMediaPolicy(
        sensitiveAction: .blurWithReveal,
        unknownAction: .allow,
        unavailableAction: .allow,
        failureAction: .allow,
        allowReveal: true,
        allowReport: false
    )

    static let teenMessaging = SafeMediaPolicy(
        sensitiveAction: .blurWithReveal,
        unknownAction: .blurWithReveal,
        unavailableAction: .blurWithReveal,
        failureAction: .blurWithReveal,
        allowReveal: true,
        allowReport: true
    )

    static let childStrict = SafeMediaPolicy(
        sensitiveAction: .block,
        unknownAction: .block,
        unavailableAction: .block,
        failureAction: .block,
        allowReveal: false,
        allowReport: true
    )

    static let classroomStrict = SafeMediaPolicy(
        sensitiveAction: .block,
        unknownAction: .block,
        unavailableAction: .block,
        failureAction: .block,
        allowReveal: false,
        allowReport: true
    )
}
