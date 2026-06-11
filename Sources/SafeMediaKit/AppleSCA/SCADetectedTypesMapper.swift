#if canImport(SensitiveContentAnalysis)
import SensitiveContentAnalysis

// Category mapping for `SCSensitivityAnalysis.detectedTypes` (Xcode 27+ SDKs).
//
// `#if compiler(>=6.4)` is a toolchain proxy for "the compile SDK exposes
// `detectedTypes`" — not a true SDK-symbol guard. A runtime `#available`
// check alone is insufficient because the symbol does not exist in pre-27
// SDKs. The proxy only breaks on unusual combinations (a Swift >= 6.4
// compiler paired with a pre-Xcode-27 Apple SDK); both bundled toolchains
// are CI-verified: Xcode 26.x excludes this branch, Xcode 27 compiles it.
enum SCADetectedTypesMapper {
    static func contentTypes(
        from analysis: SCSensitivityAnalysis
    ) -> Set<SafeMediaContentType> {
        var contentTypes: Set<SafeMediaContentType> = []

        #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            let detectedTypes = analysis.detectedTypes

            if detectedTypes.contains(.sexuallyExplicit) {
                contentTypes.insert(.sexuallyExplicit)
            }

            if detectedTypes.contains(.goreOrViolence) {
                contentTypes.insert(.goreOrViolence)
            }
        }
        #endif

        return contentTypes
    }

    /// Whether the compile SDK and target OS expose category detection.
    /// When false, callers fall back to generic sensitive mapping.
    static var isCategoryMappingAvailable: Bool {
        #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            return true
        }
        #endif
        return false
    }
}
#endif
