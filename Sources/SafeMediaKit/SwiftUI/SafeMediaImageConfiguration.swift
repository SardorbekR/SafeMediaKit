#if canImport(SwiftUI)
import SwiftUI

public struct SafeMediaImageConfiguration: Sendable, Hashable {
    public var blurRadius: Double
    public var showsReportButton: Bool
    public var warningTitle: String
    public var warningMessage: String
    public var unavailableTitle: String
    public var unavailableMessage: String
    public var blockedTitle: String
    public var blockedMessage: String
    public var loadingTitle: String
    public var revealButtonTitle: String
    public var reportButtonTitle: String

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
    static let `default` = SafeMediaImageConfiguration()
}
#endif
