/// An in-process, unbounded verdict cache.
public actor InMemorySafeMediaVerdictCache: SafeMediaVerdictCaching {
    private var verdicts: [SafeMediaCacheKey: SafeMediaVerdict]

    /// Creates a cache with optional initial verdicts.
    public init(verdicts: [SafeMediaCacheKey: SafeMediaVerdict] = [:]) {
        self.verdicts = verdicts
    }

    /// Returns the verdict stored for a key, or `nil` when none is stored.
    public func verdict(for key: SafeMediaCacheKey) async -> SafeMediaVerdict? {
        verdicts[key]
    }

    /// Stores a verdict for a key, replacing any existing value.
    public func store(_ verdict: SafeMediaVerdict, for key: SafeMediaCacheKey) async {
        verdicts[key] = verdict
    }

    /// Removes every stored verdict.
    public func removeAll() {
        verdicts.removeAll()
    }
}
