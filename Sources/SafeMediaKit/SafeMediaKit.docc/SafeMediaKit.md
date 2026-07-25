# ``SafeMediaKit``

Use Apple's SensitiveContentAnalysis framework through on-device policy, caching, live-stream, and UI layers.

## Overview

SafeMediaKit turns an analysis outcome into an app-specific ``SafeMediaDecision``. Its bundled SwiftUI and UIKit image views apply that decision before displaying media, and an optional finite-media cache avoids repeating analysis within the current process. On iOS 26 and later, the stream engine applies live-video detections while Apple's attached pipeline censors subsequent frames.

> Important: Apple's developer agreement prohibits transmitting information about whether SensitiveContentAnalysis flagged an image or video off the device. Keep verdicts and decisions local. Do not send them to analytics, remote logs, synced storage, or report payloads.

Start by enabling Apple's capability and creating an engine. For deterministic previews and unit tests, use the companion `SafeMediaKitTesting` library.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:TestingWithoutExplicitContent>
- <doc:IntegratingLiveVideoStreams>

### Engine

- ``SafeMediaEngine``
- ``AppleSensitiveContentAnalyzer``
- ``InMemorySafeMediaVerdictCache``
- ``SafeMediaCacheKey``

### Live Video

- ``SafeMediaStreamEngine``
- ``SafeMediaStreamAnalyzing``
- ``SafeMediaStreamEvent``
- ``SafeMediaStreamSession``
- ``AppleSensitiveContentStreamAnalyzer``

### Policy

- ``SafeMediaPolicy``
- ``SafeMediaPolicy/adultMinimal``
- ``SafeMediaPolicy/teenMessaging``
- ``SafeMediaPolicy/childStrict``
- ``SafeMediaPolicy/classroomStrict``
- ``SafeMediaContext``
- ``SafeMediaDecision``
- ``SafeMediaPolicy/streamSensitiveAction``

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
