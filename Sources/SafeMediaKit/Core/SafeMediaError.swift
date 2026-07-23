/// Errors that can prevent media from being loaded or analyzed.
public enum SafeMediaError: Error, Sendable, Equatable {
    /// The current platform doesn't support the requested operation.
    case unsupportedPlatform

    /// The analyzer doesn't support the supplied media type.
    case unsupportedMediaType

    /// The image couldn't be loaded from a local file or decoded.
    case imageLoadingFailed

    /// Analysis failed with the associated diagnostic message.
    case analysisFailed(String)
}
