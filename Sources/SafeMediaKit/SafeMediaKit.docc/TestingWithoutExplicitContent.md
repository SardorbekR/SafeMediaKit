# Testing Without Explicit Content

Exercise safe, sensitive, and unavailable states without adding explicit media to your project.

## Use deterministic mocks

Add the `SafeMediaKitTesting` product to a test, preview, or demo target. Its `MockSafeMediaAnalyzer` returns the result you provide:

```swift
import SafeMediaKit
import SafeMediaKitTesting

let engine = SafeMediaEngine(
    analyzer: MockSafeMediaAnalyzer(result: .success(.mockSensitive))
)
```

The included fixtures cover the common states:

- `mockSafe` produces an available, non-sensitive verdict.
- `mockSensitive` produces an available sensitive verdict.
- `mockUnknownUnavailable` produces an unknown verdict with analysis disabled.
- `mockSensitiveVideo` produces a sensitive stream verdict with all three
  video guidance flags enabled.

Use these values in unit tests and previews to verify policy decisions, blur and block states, reveal behavior, report controls, and unavailable-state copy. They are deterministic and don't depend on entitlements, device settings, or Apple's model.

For live-video flows, `MockStreamAnalyzer` can emit an ordered script without
explicit content:

```swift
@MainActor
func makeMockStreamEngine() -> SafeMediaStreamEngine {
    let analyzer = MockStreamAnalyzer(
        events: [.success(.mockSafe), .success(.mockSensitiveVideo)]
    )
    return SafeMediaStreamEngine(analyzer: analyzer)
}
```

Each start creates a fresh event stream. For cancellation tests, use the
`makeEventStream` initializer with a manually controlled
`AsyncThrowingStream`; no delays or real media are required. A successful
script remains active until the session is cancelled, just like a live stream.
Sensitive script entries pause delivery until the engine or test calls
`continueStream()`; a scripted failure ends the stream immediately.

## Test Apple's analyzer with its QR profile

Apple provides a non-explicit QR image and a special test profile that make SensitiveContentAnalysis report the image as sensitive. Follow Apple's [testing guide](https://developer.apple.com/documentation/sensitivecontentanalysis/testing-your-app-s-response-to-sensitive-media) on the development device:

1. Download Apple's test image or test video.
2. Download the Sensitive Content Analysis test profile.
3. Install the downloaded profile. Downloading it is not the same as installing it. On iPhone or iPad, open Settings, tap Profile Downloaded, then tap Install. If that entry is no longer visible, download the profile again. You can confirm installed profiles under Settings > General > VPN & Device Management. On Mac, open the downloaded profile, then open System Settings > General > Device Management and install it from the Downloaded section.
4. Restart the device so the profile takes effect.
5. Analyze the test media through your app and verify the intervention flow.

The profile must be installed and active for the QR image to produce a sensitive result. Keep this device-only flow out of automated tests; use `SafeMediaKitTesting` for CI.
