public enum SafeMediaAvailability: Sendable, Hashable {
    case available
    case unavailable(SafeMediaUnavailableReason)
}

public enum SafeMediaUnavailableReason: Sendable, Hashable {
    case unsupportedPlatform
    case analysisPolicyDisabled
    case missingFramework
    case unsupportedMediaType
}
