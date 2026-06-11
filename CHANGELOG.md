# Changelog

## 0.1.0 - Unreleased

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
