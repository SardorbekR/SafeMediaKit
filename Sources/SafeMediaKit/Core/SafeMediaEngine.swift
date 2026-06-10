public actor SafeMediaEngine {
    private let analyzer: any SafeMediaAnalyzing
    private let cache: (any SafeMediaVerdictCaching)?

    public init(
        analyzer: any SafeMediaAnalyzing,
        cache: (any SafeMediaVerdictCaching)? = nil
    ) {
        self.analyzer = analyzer
        self.cache = cache
    }

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
            let verdict = SafeMediaVerdict(
                sensitivity: .unknown,
                contentTypes: [],
                guidance: .none,
                availability: .available
            )
            return SafeMediaDecision(
                action: policy.failureAction,
                verdict: verdict,
                context: context,
                policy: policy,
                reason: .analysisFailed
            )
        }
    }

    private static func decision(
        for verdict: SafeMediaVerdict,
        context: SafeMediaContext,
        policy: SafeMediaPolicy
    ) -> SafeMediaDecision {
        let action: SafeMediaAction
        let reason: SafeMediaDecisionReason

        switch (verdict.sensitivity, verdict.availability) {
        case (_, .unavailable):
            action = policy.unavailableAction
            reason = .unavailableByPolicy
        case (.safe, .available):
            action = .allow
            reason = .safe
        case (.sensitive, .available):
            action = policy.sensitiveAction
            reason = .sensitiveDetected
        case (.unknown, .available):
            action = policy.unknownAction
            reason = .unknownByPolicy
        }

        return SafeMediaDecision(
            action: action,
            verdict: verdict,
            context: context,
            policy: policy,
            reason: reason
        )
    }
}
