/// Evaluates media, consults an optional cache, and applies a policy to each
/// verdict.
public actor SafeMediaEngine {
    private let analyzer: any SafeMediaAnalyzing
    private let cache: (any SafeMediaVerdictCaching)?

    /// Creates an engine backed by an analyzer and an optional verdict cache.
    public init(
        analyzer: any SafeMediaAnalyzing,
        cache: (any SafeMediaVerdictCaching)? = nil
    ) {
        self.analyzer = analyzer
        self.cache = cache
    }

    /// Evaluates media and returns a decision. Never throws.
    ///
    /// Analyzer errors — including `CancellationError` from a cancelled task —
    /// surface as a decision using `policy.failureAction` with reason
    /// `.analysisFailed`. Callers that cancel evaluations should discard the
    /// returned decision (the bundled views guard with `Task.isCancelled`).
    ///
    /// - Parameters:
    ///   - source: The local media to evaluate.
    ///   - context: The product context for the resulting decision.
    ///   - policy: The rules used to map the verdict to an action.
    ///   - cacheKey: A stable identity for cached analysis. When `nil`, the
    ///     engine derives a key when file size or modification-date metadata is
    ///     available and otherwise skips caching.
    /// - Returns: A policy decision for the evaluation outcome.
    public func evaluate(
        _ source: SafeMediaSource,
        context: SafeMediaContext,
        policy: SafeMediaPolicy,
        cacheKey: SafeMediaCacheKey? = nil
    ) async -> SafeMediaDecision {
        let currentAvailability = await analyzer.availability()

        if case .unavailable = currentAvailability {
            let verdict = SafeMediaVerdict(
                sensitivity: .unknown,
                contentTypes: [],
                guidance: .none,
                availability: currentAvailability
            )
            return SafeMediaEngine.decision(
                for: verdict,
                context: context,
                policy: policy
            )
        }

        let resolvedCacheKey = cacheKey ?? SafeMediaCacheKeyFactory.cacheKey(for: source)

        if let resolvedCacheKey,
           let cachedVerdict = await cache?.verdict(for: resolvedCacheKey) {
            return SafeMediaEngine.decision(
                for: cachedVerdict,
                context: context,
                policy: policy
            )
        }

        do {
            let verdict = try await analyzer.analyze(source)

            if verdict.availability == .available, let resolvedCacheKey {
                await cache?.store(verdict, for: resolvedCacheKey)
            }

            return SafeMediaEngine.decision(
                for: verdict,
                context: context,
                policy: policy
            )
        } catch {
            return SafeMediaEngine.failureDecision(
                context: context,
                policy: policy
            )
        }
    }

    static func decision(
        for verdict: SafeMediaVerdict,
        context: SafeMediaContext,
        policy: SafeMediaPolicy
    ) -> SafeMediaDecision {
        let action: SafeMediaAction
        let reason: SafeMediaDecisionReason

        switch (verdict.sensitivity, verdict.availability) {
        case (.sensitive, _):
            action = policy.sensitiveAction
            reason = .sensitiveDetected
        case (.safe, .available):
            action = .allow
            reason = .safe
        case (.unknown, .available):
            action = policy.unknownAction
            reason = .unknownByPolicy
        case (.safe, .unavailable), (.unknown, .unavailable):
            // A "safe" claim from an analyzer that reports itself unavailable is
            // contradictory; treat it as unavailable rather than trusting the claim.
            action = policy.unavailableAction
            reason = .unavailableByPolicy
        }

        return SafeMediaDecision(
            action: action,
            verdict: verdict,
            context: context,
            policy: policy,
            reason: reason
        )
    }

    static func failureDecision(
        context: SafeMediaContext,
        policy: SafeMediaPolicy
    ) -> SafeMediaDecision {
        SafeMediaDecision(
            action: policy.failureAction,
            verdict: SafeMediaVerdict(
                sensitivity: .unknown,
                contentTypes: [],
                guidance: .none,
                availability: .available
            ),
            context: context,
            policy: policy,
            reason: .analysisFailed
        )
    }
}
