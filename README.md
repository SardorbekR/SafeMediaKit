# SafeMediaKit

[![CI](https://github.com/SardorbekR/SafeMediaKit/actions/workflows/ci.yml/badge.svg)](https://github.com/SardorbekR/SafeMediaKit/actions/workflows/ci.yml)
[![Swift Versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSardorbekR%2FSafeMediaKit%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/SardorbekR/SafeMediaKit)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSardorbekR%2FSafeMediaKit%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/SardorbekR/SafeMediaKit)

SafeMediaKit is a Swift-native sensitive media intervention toolkit for Apple
apps. It helps apps analyze user-provided images and video files before display,
monitor attached live-video pipelines, and apply local blur, reveal, block,
interrupt, mute, and report flows.

SafeMediaKit relies on Apple's public `SensitiveContentAnalysis` framework when available. It only works on media your app provides to it. It cannot inspect or modify content inside other apps.

Background reading: [What Apple's SensitiveContentAnalysis actually does (and doesn't)](https://dev.to/sardor_rakhimov/what-apples-sensitivecontentanalysis-actually-does-and-doesnt-1oe2) covers the framework's opt-in reality and where SafeMediaKit fits.

## What SafeMediaKit Is Not

SafeMediaKit is not a universal iPhone screen filter, Safari content blocker, Network Extension filter, Screen Time shield, backend moderation service, custom Core ML classifier, or telemetry SDK.

It does not upload media to a server and does not include telemetry.

Note for adopters: Apple's developer agreement prohibits transmitting off the device any information about whether `SensitiveContentAnalysis` flagged a given image or video. SafeMediaKit keeps verdicts in process; keep them local in your app too. Do not log them remotely, sync them, or attach them to report payloads.

## Installation

Add SafeMediaKit as a Swift Package dependency in Xcode (`File > Add Package Dependencies…`):

```text
https://github.com/SardorbekR/SafeMediaKit
```

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/SardorbekR/SafeMediaKit.git", from: "0.1.0")
]
```

Add `SafeMediaKit` to your app target. For tests and previews, add `SafeMediaKitTesting` to the relevant test or demo target.

## Platform Support

SafeMediaKit targets:

- iOS 17+
- macOS 14+
- Mac Catalyst 17+

The package does not claim watchOS, tvOS, or visionOS support.

Live-stream analysis through Apple's `SCVideoStreamAnalyzer` is available on
iOS 26+ only. Apple marks that API unavailable on macOS and Mac Catalyst.
This version requires Xcode 26 or later with Swift 6.2 or later to build.

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

Reveal state is intentionally per-view-instance for privacy. In virtualized lists such as `LazyVStack`, scrolling away and back may re-blur a revealed image. To persist reveal choices, record your own message/media ID in `onReveal` and skip re-wrapping media the user already revealed.

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

## Custom Intervention Overlay

Brand the intervention UI without rebuilding the flow. Pass a trailing `overlay` closure; it receives a `SafeMediaOverlayState` and replaces the built-in overlay for every non-allow state (blur, block, unavailable, and load failure):

```swift
SafeMediaImage(url: imageURL, context: .incomingMessage, policy: .teenMessaging) { state in
    VStack(spacing: 12) {
        Text(state.title).font(.headline)
        Text(state.message).font(.footnote)
        if state.canReveal {
            Button("Show anyway") { state.reveal() }
        }
        if state.canReport {
            Button("Report") { state.report() }
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.ultraThickMaterial)
}
```

- `state.title` / `state.message` are resolved from your `SafeMediaImageConfiguration` for the current decision; `state.decision` exposes the raw action and reason.
- `state.reveal()` unblurs and fires `onReveal`. It is a no-op when `state.canReveal` is false — custom overlays cannot bypass `block` or no-reveal policies.
- The image underneath stays blurred or hidden regardless of what the overlay draws.
- To ignore the state, write `{ _ in MyOverlay() }`. A bare `{ MyOverlay() }` matches the `onReveal` callback parameter instead of the overlay slot.
- `SafeMediaOverlayState` has a public initializer, so you can preview and test custom overlays with fabricated decisions.

UIKit: pass `overlayProvider:` to `configure(...)`. The provided view replaces the built-in stack above the redaction blur, is pinned edge-to-edge, and is rebuilt on each reconfigure or new decision.

One source note: `SafeMediaImage` is generic over its overlay. Call sites are unaffected, but explicit type annotations must become `SafeMediaImage<SensitiveMediaOverlay>` (or use `some View`).

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

`SafeMediaEngine.evaluate` never throws. Analyzer failures become `.analysisFailed` decisions using `policy.failureAction`. That includes cancellation: if the surrounding task is cancelled during analysis, `evaluate` returns a failure decision — callers that cancel evaluations should discard the result (the bundled views do).

`AppleSensitiveContentAnalyzer` is only available on platforms where the `SensitiveContentAnalysis` framework can be imported (iOS 17+, macOS 14+, Mac Catalyst 17+).

## Live Video on iOS 26+

`SafeMediaStreamEngine` monitors an attached capture input or VideoToolbox
decompression session without caching any stream verdict. Its mandatory
`@MainActor` handler is the first UI intervention point:

```swift
import SafeMediaKit
import VideoToolbox

@available(iOS 26.0, *)
@MainActor
func startIncomingVideo(
    participantID: String,
    decompressionSession: VTDecompressionSession
) async -> SafeMediaStreamSession {
    let analyzer = AppleSensitiveContentStreamAnalyzer(
        participantID: participantID,
        decompressionSession: decompressionSession
    )
    let engine = SafeMediaStreamEngine(analyzer: analyzer)

    return await engine.start(policy: .teenMessaging) { event in
        switch event {
        case .preparing:
            concealStream()
        case .ready:
            // Attachment is ready; this is not a safe-frame verdict.
            showStream()
        case .decision(let decision):
            applySynchronously(decision)
        }
    }
}
```

While analysis remains attached, Apple interrupts capture frames or blanks
decompressed frames after a detection until `continueStream()` is called.
Apply concealment directly in the handler before returning, and conceal or stop
the host pipeline before cancellation or replacement because detaching analysis
can remove that native protection. See the DocC article "Integrating Live Video
Streams" for lifecycle, reveal, cancellation, and audio-guidance details.

## Policies

SafeMediaKit separates sensitive, unknown, unavailable, and failure behavior:

| Policy | Finite sensitive | Live sensitive | Unknown | Unavailable | Failure | Reveal | Report |
|---|---|---|---|---|---|---|---|
| `adultMinimal` | `blurWithReveal` | `allow` | `allow` | `allow` | `allow` | yes | no |
| `teenMessaging` | `blurWithReveal` | `blurWithReveal` | `blurWithReveal` | `blurWithReveal` | `blurWithReveal` | yes | yes |
| `childStrict` | `block` | `interruptVideo` | `block` | `block` | `block` | no | yes |

`classroomStrict` remains as a deprecated alias for `childStrict`. The two have always been identical in every field.

Preset names are UX defaults, not legal classifications, age-verification mechanisms, or safety guarantees. Host apps remain responsible for account policy, parental consent, and age-assurance requirements.

Blur radius: the bundled SwiftUI/UIKit views use `SafeMediaImageConfiguration.blurRadius`. `SafeMediaPolicy.blurRadius` is carried on the policy for custom UIs that render decisions themselves.

## Testing With Mocks

Use `SafeMediaKitTesting` to test UI states without explicit content:

```swift
import SafeMediaKit
import SafeMediaKitTesting

let engine = SafeMediaEngine(
    analyzer: MockSafeMediaAnalyzer(result: .success(.mockSensitive))
)

@MainActor
func makeMockStreamEngine() -> SafeMediaStreamEngine {
    SafeMediaStreamEngine(
        analyzer: MockStreamAnalyzer(events: [.success(.mockSensitiveVideo)])
    )
}
```

Mock fixtures include:

- `.mockSafe`
- `.mockSensitive`
- `.mockSensitiveVideo`
- `.mockUnknownUnavailable`

## Testing Apple's Analyzer

Do not commit explicit test media. Apple documents a QR-code/profile testing flow for triggering sensitive results without storing or displaying explicit content:

https://developer.apple.com/documentation/sensitivecontentanalysis/testing-your-app-s-response-to-sensitive-media

SafeMediaKit's CI does not depend on Apple's QR profile, entitlements, user settings, or real positive detection.

## Why Am I Always Getting Unavailable?

Apple Sensitive Content Analysis is only active when the host app has the entitlement and either Sensitive Content Warning or Communication Safety is active. If neither setting is active, Apple's `analysisPolicy` is `.disabled` and SafeMediaKit cannot detect sensitive content through Apple SCA.

To enable Apple's user preference manually: Settings > Privacy & Security > Sensitive Content Warning.

Apps can open their own Settings page with `UIApplication.openSettingsURLString`, but SafeMediaKit does not use undocumented Settings URLs and does not claim to deep-link directly to the Sensitive Content Warning pane.

## Demo

`Examples/SafeMediaChatDemo` contains a copy-paste SwiftUI demo showing safe, sensitive, and unavailable states with mock analyzers — no explicit media. See its README for setup.

## Localization

All user-facing strings in the default SwiftUI and UIKit intervention UI are configurable:

```swift
let configuration = SafeMediaImageConfiguration(
    warningTitle: String(localized: "This may be sensitive"),
    warningMessage: String(localized: "You can choose whether to view it."),
    unavailableTitle: String(localized: "Sensitive Content Analysis is off"),
    unavailableMessage: String(localized: "To use Apple sensitive-content warnings, turn on Sensitive Content Warning in Settings > Privacy & Security, or enable Communication Safety through Screen Time."),
    blockedTitle: String(localized: "Media hidden"),
    blockedMessage: String(localized: "This media is hidden by the current safety policy."),
    loadingTitle: String(localized: "Scanning media"),
    revealButtonTitle: String(localized: "Show"),
    reportButtonTitle: String(localized: "Report")
)

SafeMediaImage(
    url: imageURL,
    context: .incomingMessage,
    policy: .teenMessaging,
    configuration: configuration
)
```

The same `configuration:` parameter exists on `SafeMediaImageView.configure(...)`.

## Privacy

SafeMediaKit processes local files, in-memory media, and attached live-video
inputs on device. The package does not download remote URLs, upload media, log
media URLs by default, include analytics, or cache live-stream verdicts.

## Xcode 27 Category Mapping

When compiled with an SDK that exposes `SCSensitivityAnalysis.detectedTypes`, SafeMediaKit maps Apple's `sexuallyExplicit` and `goreOrViolence` categories into SDK-level content types behind runtime availability checks. With older SDKs, SafeMediaKit falls back to generic sensitive-content mapping.

## Roadmap

- Video thumbnail and `AVPlayer` polish
- A bundled live-stream intervention view, if adopter demand warrants one
- More category-aware policies when newer Apple APIs are broadly available
- Snapshot/UI tests

## References

- SensitiveContentAnalysis: https://developer.apple.com/documentation/sensitivecontentanalysis
- `SCSensitivityAnalyzer`: https://developer.apple.com/documentation/sensitivecontentanalysis/scsensitivityanalyzer
- `SCVideoStreamAnalyzer`: https://developer.apple.com/documentation/sensitivecontentanalysis/scvideostreamanalyzer
- Entitlement: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.sensitivecontentanalysis.client
- Sensitive Content Warning settings: https://support.apple.com/guide/iphone/receive-warnings-about-sensitive-content-iphede874992/ios
- `UIApplication.openSettingsURLString`: https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring
- App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/

## Contributing

See `CONTRIBUTING.md`.
