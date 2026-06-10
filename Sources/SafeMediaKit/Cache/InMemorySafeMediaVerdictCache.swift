public actor InMemorySafeMediaVerdictCache: SafeMediaVerdictCaching {
    private var verdicts: [SafeMediaCacheKey: SafeMediaVerdict]

    public init(verdicts: [SafeMediaCacheKey: SafeMediaVerdict] = [:]) {
        self.verdicts = verdicts
    }

    public func verdict(for key: SafeMediaCacheKey) async -> SafeMediaVerdict? {
        verdicts[key]
    }

    public func store(_ verdict: SafeMediaVerdict, for key: SafeMediaCacheKey) async {
        verdicts[key] = verdict
    }

    public func removeAll() {
        verdicts.removeAll()
    }
}
