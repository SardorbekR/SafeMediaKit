public struct SafeMediaDecision: Sendable, Hashable {
    public let action: SafeMediaAction
    public let verdict: SafeMediaVerdict
    public let context: SafeMediaContext
    public let policy: SafeMediaPolicy
    public let reason: SafeMediaDecisionReason

    public init(
        action: SafeMediaAction,
        verdict: SafeMediaVerdict,
        context: SafeMediaContext,
        policy: SafeMediaPolicy,
        reason: SafeMediaDecisionReason
    ) {
        self.action = action
        self.verdict = verdict
        self.context = context
        self.policy = policy
        self.reason = reason
    }
}

public enum SafeMediaDecisionReason: Sendable, Hashable {
    case safe
    case sensitiveDetected
    case unknownByPolicy
    case unavailableByPolicy
    case analysisFailed
}
