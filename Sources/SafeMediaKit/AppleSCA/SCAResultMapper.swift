#if canImport(SensitiveContentAnalysis)
import SensitiveContentAnalysis

enum SCAResultMapper {
    static func map(_ analysis: SCSensitivityAnalysis) -> SafeMediaVerdict {
        SafeMediaVerdict(
            sensitivity: analysis.isSensitive ? .sensitive : .safe,
            contentTypes: analysis.isSensitive ? [.nudity] : [],
            guidance: .none,
            availability: .available
        )
    }

    // TODO: Map `SCSensitivityAnalysis.detectedTypes` (`sexuallyExplicit`,
    // `goreOrViolence`) to `SafeMediaContentType` once CI compiles with an
    // Apple SDK that exposes the symbol (announced for the OS 27 cycle).
    // Runtime `#available` checks alone are insufficient while the symbol is
    // absent from the compile SDK, so this integration must land in a
    // separate availability-gated file when the toolchain supports it.
}
#endif
