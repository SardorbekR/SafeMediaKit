#if canImport(SensitiveContentAnalysis)
import SensitiveContentAnalysis

// Category mapping for `SCSensitivityAnalysis.detectedTypes` (Xcode 27+ SDKs).
//
// `#if canImport(SensitiveContentAnalysis, _version: 145)` gates on the
// framework's module version in the compile SDK: 130.4.1 in the iOS 26 SDKs,
// 145 in the Xcode 27 SDK that introduces `detectedTypes`. A runtime
// `#available` check alone is insufficient because the symbol does not exist
// in pre-27 SDKs. Unlike the previous `#if compiler(>=6.4)` toolchain proxy,
// this stays correct when a newer compiler builds against an older SDK. The
// `_version:` spelling is underscored, so both bundled toolchains are
// CI-verified: Xcode 26.x excludes this branch, Xcode 27 compiles it.
enum SCADetectedTypesMapper {
    static func contentTypes(
        from analysis: SCSensitivityAnalysis
    ) -> Set<SafeMediaContentType> {
        var contentTypes: Set<SafeMediaContentType> = []

        #if canImport(SensitiveContentAnalysis, _version: 145)
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
        #if canImport(SensitiveContentAnalysis, _version: 145)
        if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *) {
            return true
        }
        #endif
        return false
    }
}
#endif
