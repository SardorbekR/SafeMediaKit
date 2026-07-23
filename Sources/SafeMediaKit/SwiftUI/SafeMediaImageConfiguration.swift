#if canImport(SwiftUI)
import SwiftUI

/// Text, controls, and presentation settings for the bundled media views.
public struct SafeMediaImageConfiguration: Sendable, Hashable {
    /// The blur radius used by ``SafeMediaImage``.
    public var blurRadius: Double

    /// Whether bundled overlays can show a report button when policy permits it.
    public var showsReportButton: Bool

    /// The title used when unavailable and blocking copy don't apply.
    public var warningTitle: String

    /// The message used when unavailable and blocking copy don't apply.
    public var warningMessage: String

    /// The title used for an unavailable-by-policy decision.
    public var unavailableTitle: String

    /// The message used for an unavailable-by-policy decision.
    public var unavailableMessage: String

    /// The title used for a blocked decision other than an unavailable one.
    public var blockedTitle: String

    /// The message used for a blocked decision other than an unavailable one.
    public var blockedMessage: String

    /// The text and accessibility label ``SafeMediaImage`` shows while loading
    /// or evaluating media.
    public var loadingTitle: String

    /// The title of the bundled reveal button.
    public var revealButtonTitle: String

    /// The title of the bundled report button.
    public var reportButtonTitle: String

    /// Creates a configuration for the bundled media views. Negative initial
    /// blur radii are clamped to zero.
    public init(
        blurRadius: Double = 18,
        showsReportButton: Bool = true,
        warningTitle: String = "This may be sensitive",
        warningMessage: String = "You can choose whether to view it.",
        unavailableTitle: String = "Sensitive Content Analysis is off",
        unavailableMessage: String = "To use Apple sensitive-content warnings, turn on Sensitive Content Warning in Settings > Privacy & Security, or enable Communication Safety through Screen Time.",
        blockedTitle: String = "Media hidden",
        blockedMessage: String = "This media is hidden by the current safety policy.",
        loadingTitle: String = "Scanning media",
        revealButtonTitle: String = "Show",
        reportButtonTitle: String = "Report"
    ) {
        self.blurRadius = max(0, blurRadius)
        self.showsReportButton = showsReportButton
        self.warningTitle = warningTitle
        self.warningMessage = warningMessage
        self.unavailableTitle = unavailableTitle
        self.unavailableMessage = unavailableMessage
        self.blockedTitle = blockedTitle
        self.blockedMessage = blockedMessage
        self.loadingTitle = loadingTitle
        self.revealButtonTitle = revealButtonTitle
        self.reportButtonTitle = reportButtonTitle
    }
}

public extension SafeMediaImageConfiguration {
    /// The standard warning, unavailable, blocked, loading, and button copy.
    static let `default` = SafeMediaImageConfiguration()
}
#endif
