public protocol SafeMediaVerdictCaching: Sendable {
    func verdict(for key: SafeMediaCacheKey) async -> SafeMediaVerdict?
    func store(_ verdict: SafeMediaVerdict, for key: SafeMediaCacheKey) async
}
