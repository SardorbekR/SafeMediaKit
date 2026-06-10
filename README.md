# SafeMediaKit

SafeMediaKit is a Swift-native sensitive media intervention toolkit for Apple apps. It helps apps analyze user-provided images and videos before display and present privacy-preserving blur, reveal, block, and report flows.

SafeMediaKit relies on Apple's public `SensitiveContentAnalysis` framework when available. It only works on media your app provides to it. It cannot inspect or modify content inside other apps.

## What SafeMediaKit Is Not

SafeMediaKit is not a universal iPhone screen filter, Safari content blocker, Network Extension filter, Screen Time shield, backend moderation service, custom Core ML classifier, or telemetry SDK.

It does not upload media to a server and does not include telemetry.

## Installation

Add this repository as a Swift Package dependency in Xcode, then add `SafeMediaKit` to your app target.

For tests and previews, add `SafeMediaKitTesting` to the relevant test or demo target.

## Platform Support

SafeMediaKit targets:

- iOS 17+
- macOS 14+
- Mac Catalyst 17+

The package does not claim watchOS, tvOS, or visionOS support.

## Entitlement Setup

The host app must enable Apple's Sensitive Content Analysis capability with the entitlement:

```text
com.apple.developer.sensitivecontentanalysis.client = analysis
```

Apple's framework may still report `analysisPolicy == .disabled` when the entitlement is missing, Sensitive Content Warning is off, Communication Safety is not active, or the app-specific toggle is disabled. SafeMediaKit maps that state to `.unavailable(.analysisPolicyDisabled)` and applies your configured unavailable policy.

## SwiftUI Usage

```swift
import SafeMediaKit
import SwiftUI

struct MessageImage: View {
    let imageURL: URL
    let engine: SafeMediaEngine

    var body: some View {
        SafeMediaImage(
            url: imageURL,
            engine: engine,
            context: .incomingMessage,
            policy: .teenMessaging,
            onReveal: {
                print("User revealed sensitive image")
            },
            onReport: {
                print("User reported sensitive image")
            }
        )
        .frame(width: 240, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
```

You can also inject the engine through the SwiftUI environment:

```swift
RootView()
    .environment(\.safeMediaEngine, engine)
```

Then use:

```swift
SafeMediaImage(
    url: imageURL,
    context: .incomingMessage,
    policy: .teenMessaging
)
```

## UIKit Usage

```swift
import SafeMediaKit
import UIKit

let imageView = SafeMediaImageView()
imageView.configure(
    imageURL: imageURL,
    engine: engine,
    context: .incomingMessage,
    policy: .teenMessaging,
    onReveal: {
        print("User revealed sensitive image")
    },
    onReport: {
        print("User reported sensitive image")
    }
)
```

`SafeMediaImageView` is compiled only when UIKit is available, so pure macOS builds do not expose it.

## Direct Analyzer Usage

```swift
import SafeMediaKit

let analyzer = AppleSensitiveContentAnalyzer()
let engine = SafeMediaEngine(
    analyzer: analyzer,
    cache: InMemorySafeMediaVerdictCache()
)

let decision = await engine.evaluate(
    .imageFile(imageURL),
    context: .incomingMessage,
    policy: .teenMessaging
)
```

`SafeMediaEngine.evaluate` never throws. Analyzer failures become `.analysisFailed` decisions using `policy.failureAction`.

## Policies

SafeMediaKit separates sensitive, unknown, unavailable, and failure behavior:

| Policy | Sensitive | Unknown | Unavailable | Failure | Reveal | Report |
|---|---|---|---|---|---|---|
| `adultMinimal` | `blurWithReveal` | `allow` | `allow` | `allow` | yes | no |
| `teenMessaging` | `blurWithReveal` | `blurWithReveal` | `blurWithReveal` | `blurWithReveal` | yes | yes |
| `childStrict` | `block` | `block` | `block` | `block` | no | yes |
| `classroomStrict` | `block` | `block` | `block` | `block` | no | yes |

Preset names are UX defaults, not legal classifications, age-verification mechanisms, or safety guarantees. Host apps remain responsible for account policy, parental consent, and age-assurance requirements.

## Testing With Mocks

Use `SafeMediaKitTesting` to test UI states without explicit content:

```swift
import SafeMediaKit
import SafeMediaKitTesting

let engine = SafeMediaEngine(
    analyzer: MockSafeMediaAnalyzer(result: .success(.mockSensitive))
)
```

Mock fixtures include:

- `.mockSafe`
- `.mockSensitive`
- `.mockUnknownUnavailable`

## Testing Apple's Analyzer

Do not commit explicit test media. Apple documents a QR-code/profile testing flow for triggering sensitive results without storing or displaying explicit content:

https://developer.apple.com/documentation/sensitivecontentanalysis/testing-your-app-s-response-to-sensitive-media

SafeMediaKit's CI does not depend on Apple's QR profile, entitlements, user settings, or real positive detection.

## Why Am I Always Getting Unavailable?

Apple Sensitive Content Analysis is only active when the host app has the entitlement and either Sensitive Content Warning or Communication Safety is active. If neither setting is active, Apple's `analysisPolicy` is `.disabled` and SafeMediaKit cannot detect sensitive content through Apple SCA.

To enable Apple's user preference manually: Settings > Privacy & Security > Sensitive Content Warning.

Apps can open their own Settings page with `UIApplication.openSettingsURLString`, but SafeMediaKit does not use undocumented Settings URLs and does not claim to deep-link directly to the Sensitive Content Warning pane.

## Localization

All user-facing strings in the default SwiftUI and UIKit intervention UI are configurable:

```swift
SafeMediaImageConfiguration(
    warningTitle: String(localized: "This may be sensitive"),
    warningMessage: String(localized: "You can choose whether to view it."),
    revealButtonTitle: String(localized: "Show"),
    reportButtonTitle: String(localized: "Report")
)
```

## Privacy

SafeMediaKit processes only local media that your app passes to it. The package does not download remote URLs, upload media, log media URLs by default, or include analytics.

## Content Categories

The MVP maps Apple's detection result to a generic `.nudity` content type. Apple's newer `SCSensitivityAnalysis.detectedTypes` classification (`sexuallyExplicit`, `goreOrViolence`) is intentionally not referenced yet: the symbol must exist in the compile SDK, and runtime availability checks alone are not enough. Category mapping lands once CI compiles with an SDK that exposes it.

## Roadmap

- Video thumbnail and `AVPlayer` polish
- Live stream analysis through `SCVideoStreamAnalyzer`
- Category mapping via `SCSensitivityAnalysis.detectedTypes` once the compile SDK exposes it
- More category-aware policies when newer Apple APIs are broadly available
- DocC documentation
- Snapshot/UI tests

## References

- SensitiveContentAnalysis: https://developer.apple.com/documentation/sensitivecontentanalysis
- `SCSensitivityAnalyzer`: https://developer.apple.com/documentation/sensitivecontentanalysis/scsensitivityanalyzer
- Entitlement: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.sensitivecontentanalysis.client
- Sensitive Content Warning settings: https://support.apple.com/guide/iphone/receive-warnings-about-sensitive-content-iphede874992/ios
- `UIApplication.openSettingsURLString`: https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring
- App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/

## Contributing

See `CONTRIBUTING.md`.
