/// Whether an analyzer can evaluate media in the current environment.
public enum SafeMediaAvailability: Sendable, Hashable {
    /// The analyzer can attempt analysis in the current environment.
    case available

    /// The analyzer can't attempt analysis for the associated reason.
    case unavailable(SafeMediaUnavailableReason)
}

/// A reason that media analysis is unavailable.
public enum SafeMediaUnavailableReason: Sendable, Hashable {
    /// The current operating system or device doesn't support the analyzer.
    case unsupportedPlatform

    /// The system analysis policy is disabled for the app.
    case analysisPolicyDisabled

    /// The required analysis framework can't be loaded.
    case missingFramework

    /// The analyzer doesn't support the supplied media type.
    case unsupportedMediaType
}
