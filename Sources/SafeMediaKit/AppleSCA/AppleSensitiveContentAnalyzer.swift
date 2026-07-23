#if canImport(SensitiveContentAnalysis)
import Foundation
import SensitiveContentAnalysis

/// Analyzes images and video files with Apple's Sensitive Content Analysis framework.
@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, *)
public struct AppleSensitiveContentAnalyzer: SafeMediaAnalyzing {
    private let analyzer: SCSensitivityAnalyzer

    /// Creates an analyzer backed by a new `SCSensitivityAnalyzer`.
    public init() {
        self.analyzer = SCSensitivityAnalyzer()
    }

    /// Reports whether the system's sensitive-content analysis policy is enabled.
    public func availability() async -> SafeMediaAvailability {
        analyzer.analysisPolicy == .disabled
            ? .unavailable(.analysisPolicyDisabled)
            : .available
    }

    /// Analyzes a source and maps the system result to a ``SafeMediaVerdict``.
    ///
    /// - Throws: An error from the underlying system analyzer, or
    ///   `CancellationError` when video analysis is cancelled.
    public func analyze(_ source: SafeMediaSource) async throws -> SafeMediaVerdict {
        guard analyzer.analysisPolicy != .disabled else {
            return SafeMediaVerdict(
                sensitivity: .unknown,
                contentTypes: [],
                guidance: .none,
                availability: .unavailable(.analysisPolicyDisabled)
            )
        }

        switch source {
        case .imageFile(let url):
            let analysis = try await analyzer.analyzeImage(at: url)
            return SCAResultMapper.map(analysis)
        case .cgImage(let image):
            let analysis = try await analyzer.analyzeImage(image)
            return SCAResultMapper.map(analysis)
        case .videoFile(let url):
            try Task.checkCancellation()
            let analysis = try await analyzer
                .videoAnalysis(forFileAt: url)
                .hasSensitiveContent()
            try Task.checkCancellation()
            return SCAResultMapper.map(analysis)
        }
    }
}
#endif
