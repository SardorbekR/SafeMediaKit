public enum SafeMediaError: Error, Sendable, Equatable {
    case unsupportedPlatform
    case unsupportedMediaType
    case imageLoadingFailed
    case analysisFailed(String)
}
