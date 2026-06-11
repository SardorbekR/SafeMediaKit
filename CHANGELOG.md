# Changelog

## 0.2.1 - Unreleased

- VoiceOver now exposes the default overlay as one text element plus separately focusable Show/Report buttons, instead of a single combined element with custom actions. Matches the UIKit overlay's accessibility shape and makes the actions discoverable without the custom-actions gesture.

## 0.2.0 - 2026-06-11

- Added a custom overlay slot: `SafeMediaImage` is now generic over its overlay; new `overlay:` initializers receive a `SafeMediaOverlayState`.
- Added `SafeMediaOverlayState` with resolved copy, `canReveal`/`canReport` flags, and a policy-guarded `reveal()` that cannot bypass `block` or no-reveal policies.
- Added `overlayProvider:` to `SafeMediaImageView.configure(...)`; the redaction blur always stays beneath custom overlays.
- Redesigned the default overlays in SwiftUI and UIKit: per-state SF Symbols (`eye.slash.fill`, `lock.fill`, `gearshape.fill`), headline/footnote typography, capsule buttons.
- Added `SensitiveMediaOverlay.init(state:)`; the memberwise initializer gains an optional `systemImageName:` parameter.
- Source note: explicit `SafeMediaImage` type annotations must become `SafeMediaImage<SensitiveMediaOverlay>`; initializer call sites are unaffected.

## 0.1.0 - 2026-06-11

- Initial Swift Package scaffold.
- Added core media source, verdict, policy, availability, and decision models.
- Added `SafeMediaEngine` with per-evaluation availability checks and local verdict caching.
- Added Apple `SensitiveContentAnalysis` adapter.
- Added Xcode 27-gated category mapping for `detectedTypes`.
- Added SwiftUI `SafeMediaImage`.
- Added UIKit `SafeMediaImageView`.
- Added `SafeMediaKitTesting` with `MockSafeMediaAnalyzer` and mock verdict fixtures.
- Added unit tests, docs, CI, and package demo source.
- Fixed fail-open scanning window: both `SafeMediaImage` and `SafeMediaImageView` now keep media hidden until a decision is applied.
- Fixed decision mapping so a sensitive verdict always uses `sensitiveAction`, even when the verdict also reports unavailability.
- Skipped caching for files whose metadata is unreadable to avoid stale verdicts.
