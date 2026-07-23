/// An asynchronous store for media-analysis verdicts.
public protocol SafeMediaVerdictCaching: Sendable {
    /// Returns the verdict stored for a key, or `nil` when none is stored.
    func verdict(for key: SafeMediaCacheKey) async -> SafeMediaVerdict?

    /// Stores a verdict for a key, replacing any existing value.
    func store(_ verdict: SafeMediaVerdict, for key: SafeMediaCacheKey) async
}
