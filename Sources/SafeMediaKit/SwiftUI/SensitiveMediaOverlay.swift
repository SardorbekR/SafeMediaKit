#if canImport(SwiftUI)
import SwiftUI

/// The bundled SwiftUI intervention overlay for a non-allow decision.
@available(iOS 17.0, macOS 14.0, macCatalyst 17.0, *)
public struct SensitiveMediaOverlay: View {
    private let title: String
    private let message: String
    private let revealButtonTitle: String
    private let reportButtonTitle: String
    private let showsRevealButton: Bool
    private let showsReportButton: Bool
    private let systemImageName: String?
    private let onReveal: @MainActor @Sendable () -> Void
    private let onReport: @MainActor @Sendable () -> Void

    /// Builds the default overlay for a decision state.
    public init(state: SafeMediaOverlayState) {
        self.init(
            title: state.title,
            message: state.message,
            revealButtonTitle: state.configuration.revealButtonTitle,
            reportButtonTitle: state.configuration.reportButtonTitle,
            showsRevealButton: state.canReveal,
            showsReportButton: state.canReport,
            systemImageName: SafeMediaOverlayGlyph.systemImageName(for: state.decision),
            onReveal: state.reveal,
            onReport: state.report
        )
    }

    /// Builds an overlay from resolved copy, controls, and action handlers.
    public init(
        title: String,
        message: String,
        revealButtonTitle: String,
        reportButtonTitle: String,
        showsRevealButton: Bool,
        showsReportButton: Bool,
        systemImageName: String? = nil,
        onReveal: @escaping @MainActor @Sendable () -> Void,
        onReport: @escaping @MainActor @Sendable () -> Void
    ) {
        self.title = title
        self.message = message
        self.revealButtonTitle = revealButtonTitle
        self.reportButtonTitle = reportButtonTitle
        self.showsRevealButton = showsRevealButton
        self.showsReportButton = showsReportButton
        self.systemImageName = systemImageName
        self.onReveal = onReveal
        self.onReport = onReport
    }

    /// The adaptive warning content and available actions.
    public var body: some View {
        // Small thumbnails cannot fit icon + wrapped text + buttons; the
        // compact variant drops the icon and tightens padding so the message
        // wraps instead of truncating.
        ViewThatFits(in: .vertical) {
            overlayStack(showsIcon: true, padding: 20)
            overlayStack(showsIcon: false, padding: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .foregroundStyle(.primary)
    }

    private func overlayStack(showsIcon: Bool, padding: CGFloat) -> some View {
        VStack(spacing: 12) {
            if showsIcon, let systemImageName {
                Image(systemName: systemImageName)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            // Texts merge into a single VoiceOver stop; the buttons stay
            // separate focusable elements so reveal/report are discoverable
            // without knowing the custom-actions gesture (matches the UIKit
            // overlay's accessibility shape).
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title). \(message)")

            if showsRevealButton || showsReportButton {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        actionButtons
                    }
                    VStack(spacing: 8) {
                        actionButtons
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(padding)
        .frame(maxWidth: 280)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if showsRevealButton {
            Button(revealButtonTitle, action: onReveal)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .accessibilityLabel(revealButtonTitle)
        }

        if showsReportButton {
            Button(reportButtonTitle, action: onReport)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityLabel(reportButtonTitle)
        }
    }
}
#endif
