#if canImport(SwiftUI)
import Foundation

/// Everything a custom intervention overlay needs to render and act on a
/// decision. Passed to the `overlay:` closure of `SafeMediaImage` and the
/// `overlayProvider:` of `SafeMediaImageView`.
///
/// The public initializer lets host apps construct states with fabricated
/// decisions for previews and tests of their custom overlays.
public struct SafeMediaOverlayState: Sendable {
    /// The decision the overlay represents.
    public let decision: SafeMediaDecision

    /// The copy and control configuration for the overlay.
    public let configuration: SafeMediaImageConfiguration

    /// Copy resolved from `configuration` for this decision: unavailable copy
    /// for `.unavailableByPolicy`, blocked copy for `.block`, warning copy
    /// otherwise.
    public let title: String

    /// The resolved explanatory message for the current decision.
    public let message: String

    /// True only when an image is loaded, the action is `.blurWithReveal`,
    /// and the policy allows revealing.
    public let canReveal: Bool

    /// Advisory flag for showing a report control.
    public let canReport: Bool

    /// Reveals the media and fires the host `onReveal` callback. No-op when
    /// `canReveal` is false — custom overlays cannot bypass `block` or
    /// no-reveal policies.
    public let reveal: @MainActor @Sendable () -> Void

    /// Fires the host `onReport` callback. Not gated on `canReport`.
    public let report: @MainActor @Sendable () -> Void

    /// Creates the state passed to a custom or bundled intervention overlay.
    public init(
        decision: SafeMediaDecision,
        configuration: SafeMediaImageConfiguration,
        hasImage: Bool,
        onReveal: @escaping @MainActor @Sendable () -> Void,
        onReport: @escaping @MainActor @Sendable () -> Void
    ) {
        self.decision = decision
        self.configuration = configuration

        switch decision.reason {
        case .unavailableByPolicy:
            self.title = configuration.unavailableTitle
            self.message = configuration.unavailableMessage
        default:
            if decision.action == .block {
                self.title = configuration.blockedTitle
                self.message = configuration.blockedMessage
            } else {
                self.title = configuration.warningTitle
                self.message = configuration.warningMessage
            }
        }

        let canReveal = hasImage
            && decision.action == .blurWithReveal
            && decision.policy.allowReveal
        self.canReveal = canReveal
        self.canReport = configuration.showsReportButton && decision.policy.allowReport

        self.reveal = {
            guard canReveal else {
                return
            }
            onReveal()
        }
        self.report = onReport
    }
}

/// Shared icon mapping for the bundled SwiftUI and UIKit default overlays.
enum SafeMediaOverlayGlyph {
    static func systemImageName(for decision: SafeMediaDecision) -> String {
        if decision.reason == .unavailableByPolicy {
            return "gearshape.fill"
        }
        return decision.action == .block ? "lock.fill" : "eye.slash.fill"
    }
}
#endif
