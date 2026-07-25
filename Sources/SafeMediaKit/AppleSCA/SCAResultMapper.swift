#if canImport(SensitiveContentAnalysis)
import SensitiveContentAnalysis

enum SCAResultMapper {
    static func map(_ analysis: SCSensitivityAnalysis) -> SafeMediaVerdict {
        SafeMediaVerdict(
            sensitivity: analysis.isSensitive ? .sensitive : .safe,
            contentTypes: contentTypes(from: analysis),
            guidance: .none,
            availability: .available
        )
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
    @available(iOS 26.0, *)
    static func mapStream(_ analysis: SCSensitivityAnalysis) -> SafeMediaVerdict {
        SafeMediaVerdict(
            sensitivity: analysis.isSensitive ? .sensitive : .safe,
            contentTypes: contentTypes(from: analysis),
            guidance: SafeMediaGuidance(
                shouldIndicateSensitivity: analysis.shouldIndicateSensitivity,
                shouldInterruptVideo: analysis.shouldInterruptVideo,
                shouldMuteAudio: analysis.shouldMuteAudio
            ),
            availability: .available
        )
    }
    #endif

    private static func contentTypes(
        from analysis: SCSensitivityAnalysis
    ) -> Set<SafeMediaContentType> {
        guard analysis.isSensitive else {
            return []
        }

        var contentTypes = SCADetectedTypesMapper.contentTypes(from: analysis)

        if contentTypes.isEmpty {
            // With category detection available, a sensitive result without a
            // mapped category is generic; without it, Apple SCA detects nudity.
            contentTypes.insert(
                SCADetectedTypesMapper.isCategoryMappingAvailable
                    ? .unknownSensitive
                    : .nudity
            )
        }

        return contentTypes
    }
}
#endif
