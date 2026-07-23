# ``SafeMediaKit``

Use Apple's SensitiveContentAnalysis framework through a policy, caching, and UI layer that keeps analysis on device and keeps unreviewed media hidden until a decision is ready.

## Overview

SafeMediaKit turns an analysis outcome into an app-specific ``SafeMediaDecision``. Its bundled SwiftUI and UIKit views apply that decision before displaying media, and an optional cache avoids repeating analysis within the current process.

> Important: Apple's developer agreement prohibits transmitting information about whether SensitiveContentAnalysis flagged an image or video off the device. Keep verdicts and decisions local. Do not send them to analytics, remote logs, synced storage, or report payloads.

Start by enabling Apple's capability and creating an engine. For deterministic previews and unit tests, use the companion `SafeMediaKitTesting` library.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:TestingWithoutExplicitContent>

### Engine

- ``SafeMediaEngine``
- ``AppleSensitiveContentAnalyzer``
- ``InMemorySafeMediaVerdictCache``
- ``SafeMediaCacheKey``

### Policy

- ``SafeMediaPolicy``
- ``SafeMediaPolicy/adultMinimal``
- ``SafeMediaPolicy/teenMessaging``
- ``SafeMediaPolicy/childStrict``
- ``SafeMediaPolicy/classroomStrict``
- ``SafeMediaContext``
- ``SafeMediaDecision``

### SwiftUI

- ``SafeMediaImage``
- ``SafeMediaOverlayState``
- ``SensitiveMediaOverlay``
- ``SafeMediaImageConfiguration``

### UIKit

- ``SafeMediaImageView``

### Availability Handling

- ``SafeMediaAvailability``
- ``SafeMediaUnavailableReason``
