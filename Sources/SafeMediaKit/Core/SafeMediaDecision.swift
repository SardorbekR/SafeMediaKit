/// A policy decision for evaluated media.
public struct SafeMediaDecision: Sendable, Hashable {
    /// The intervention the host app should apply.
    public let action: SafeMediaAction

    /// The verdict associated with this decision.
    public let verdict: SafeMediaVerdict

    /// The product context supplied for the evaluation.
    public let context: SafeMediaContext

    /// The policy used to select the action.
    public let policy: SafeMediaPolicy

    /// The branch of the decision process that selected the action.
    public let reason: SafeMediaDecisionReason

    /// Creates a decision from an action, verdict, context, policy, and reason.
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

/// The condition that produced a media decision.
public enum SafeMediaDecisionReason: Sendable, Hashable {
    /// The analyzer reported the media as safe.
    case safe

    /// The analyzer detected sensitive content.
    case sensitiveDetected

    /// The analyzer couldn't classify the media, so the unknown policy applied.
    case unknownByPolicy

    /// Analysis was unavailable, so the unavailable policy applied.
    case unavailableByPolicy

    /// Analysis or media loading failed, so the failure policy applied.
    case analysisFailed
}
