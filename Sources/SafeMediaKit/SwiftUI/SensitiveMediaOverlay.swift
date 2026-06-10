#if canImport(SwiftUI)
import SwiftUI

@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, *)
public struct SensitiveMediaOverlay: View {
    private let title: String
    private let message: String
    private let revealButtonTitle: String
    private let reportButtonTitle: String
    private let showsRevealButton: Bool
    private let showsReportButton: Bool
    private let onReveal: @MainActor @Sendable () -> Void
    private let onReport: @MainActor @Sendable () -> Void

    public init(
        title: String,
        message: String,
        revealButtonTitle: String,
        reportButtonTitle: String,
        showsRevealButton: Bool,
        showsReportButton: Bool,
        onReveal: @escaping @MainActor @Sendable () -> Void,
        onReport: @escaping @MainActor @Sendable () -> Void
    ) {
        self.title = title
        self.message = message
        self.revealButtonTitle = revealButtonTitle
        self.reportButtonTitle = reportButtonTitle
        self.showsRevealButton = showsRevealButton
        self.showsReportButton = showsReportButton
        self.onReveal = onReveal
        self.onReport = onReport
    }

    public var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(nil)

            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .lineLimit(nil)

            HStack(spacing: 10) {
                if showsRevealButton {
                    Button(revealButtonTitle, action: onReveal)
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(revealButtonTitle)
                }

                if showsReportButton {
                    Button(reportButtonTitle, action: onReport)
                        .buttonStyle(.bordered)
                        .accessibilityLabel(reportButtonTitle)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}
#endif
