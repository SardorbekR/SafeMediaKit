# Getting Started with SafeMediaKit

Enable Sensitive Content Analysis, check whether the analyzer can attempt analysis, and evaluate media before displaying it.

## Enable the capability

In your app target's Signing & Capabilities settings, add the Sensitive Content Analysis capability. Xcode adds the `com.apple.developer.sensitivecontentanalysis.client` entitlement with an array containing `analysis`:

```xml
<key>com.apple.developer.sensitivecontentanalysis.client</key>
<array>
    <string>analysis</string>
</array>
```

This is a standard Xcode capability, not a managed-capability request. Xcode adds the entitlement when you enable the capability; there is no approval process.

## Create an engine

Create ``AppleSensitiveContentAnalyzer`` and optionally provide an in-process cache:

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

``SafeMediaEngine/evaluate(_:context:policy:cacheKey:)`` never throws. It maps analyzer failures to the policy's `failureAction`, and the bundled views keep media hidden until they can apply a decision.

For SwiftUI, pass the engine directly to ``SafeMediaImage`` or install it in the environment:

```swift
RootView()
    .environment(\.safeMediaEngine, engine)
```

## Treat unavailability as normal

Check availability before presenting UI that assumes analysis can run:

```swift
switch await analyzer.availability() {
case .available:
    // Sensitive Content Analysis can evaluate media.
    break
case .unavailable:
    // Present your app's setup instructions.
    break
}
```

An unavailable result is a normal device state, not necessarily an integration error. Sensitive Content Warning is opt-in for adults. Communication Safety is on by default for children under 18 who are signed in to their Apple Account and are part of a Family Sharing group on devices running the latest software, although availability and age thresholds vary by country or region. Either setting can be changed, and a person can disable analysis for an individual app.

SafeMediaKit represents these states with ``SafeMediaAvailability/unavailable(_:)`` and applies the policy's `unavailableAction`. Choose that action for your product context instead of assuming analysis will always be enabled.

Apple doesn't provide a documented public API that opens the Sensitive Content Warning or Communication Safety pane directly. If analysis is disabled, show instructions such as:

> Open Settings (System Settings on Mac), go to Privacy & Security > Sensitive Content Warning, and turn on Sensitive Content Warning for this app. For a child account, review Communication Safety in Screen Time.

An iOS app may open its own Settings page with `UIApplication.openSettingsURLString`, but the person still needs clear navigation instructions.
