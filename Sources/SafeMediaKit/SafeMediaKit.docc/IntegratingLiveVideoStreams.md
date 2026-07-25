# Integrating Live Video Streams

Monitor an attached iOS video pipeline, apply detection events synchronously,
and keep stream verdicts out of caches and off the network.

## Check the requirements

``AppleSensitiveContentStreamAnalyzer`` is available on iOS 26 and later. Apple
marks `SCVideoStreamAnalyzer` unavailable on macOS, Mac Catalyst, tvOS, and
visionOS. The host app needs the Sensitive Content Analysis capability and an
enabled system analysis policy, just as it does for finite media.

Create one analyzer for each stream. If a participant owns multiple streams,
use the same participant identifier for each of that person's analyzers.

SafeMediaKit supports the two attachment paths for which Apple provides
automatic post-detection censorship:

- `AVCaptureDeviceInput` for a capture stream. Apple interrupts subsequent
  frames when it detects sensitive content.
- `VTDecompressionSession` for a decoded stream. Apple replaces subsequent
  output with blank frames after a detection.

The package intentionally doesn't expose manual `CVPixelBuffer` submission in
v1. Apple doesn't document automatic rendering protection for that path, so a
generic wrapper couldn't provide the same post-detection protection.

## Attach and monitor a stream

Configure the adapter with the pipeline it should attach when the engine starts:

```swift
import AVFoundation
import SafeMediaKit
import UIKit
import VideoToolbox

@available(iOS 26.0, *)
@MainActor
final class IncomingVideoSafetyCoordinator {
    private let engine: SafeMediaStreamEngine
    private let videoView: UIView
    private let redactionView: UIView
    private let setAudioMuted: (Bool) -> Void

    private var session: SafeMediaStreamSession?
    private var canReveal = false

    init(
        participantID: String,
        decompressionSession: VTDecompressionSession,
        videoView: UIView,
        redactionView: UIView,
        setAudioMuted: @escaping (Bool) -> Void
    ) {
        let analyzer = AppleSensitiveContentStreamAnalyzer(
            participantID: participantID,
            decompressionSession: decompressionSession
        )

        self.engine = SafeMediaStreamEngine(analyzer: analyzer)
        self.videoView = videoView
        self.redactionView = redactionView
        self.setAudioMuted = setAudioMuted

        videoView.isHidden = true
        redactionView.isHidden = false
    }

    func start() async {
        // Conceal before detaching a previous analyzer or awaiting preflight.
        blockStream()
        session?.cancel()
        canReveal = false

        session = await engine.start(policy: .teenMessaging) { [weak self] event in
            guard !Task.isCancelled, let self else { return }

            // This closure is synchronous and MainActor-isolated. Apply the
            // intervention directly; don't dispatch another task first.
            self.apply(event)
        }
    }

    private func apply(_ event: SafeMediaStreamEvent) {
        switch event {
        case .preparing:
            canReveal = false
            blockStream()

        case .ready:
            // Attachment succeeded. This is not a per-frame "safe" verdict.
            setAudioMuted(false)
            showStream()

        case .decision(let decision):
            // Apple reports audio muting as guidance; the host must apply it.
            setAudioMuted(decision.verdict.guidance.shouldMuteAudio)
            canReveal = decision.action == .blurWithReveal
                && decision.policy.allowReveal

            switch decision.action {
            case .allow:
                // The engine resumes Apple's stream after this handler returns.
                showStream()
            case .blur, .blurWithReveal:
                obscureStream()
            case .block, .interruptVideo:
                blockStream()
            case .muteAudio:
                showStream()
                setAudioMuted(true)
            }
        }
    }

    func reveal() {
        guard canReveal, let session else { return }
        canReveal = false

        // Keep the redaction visible until the explicit resume call. Apple's
        // continueStream() both resumes analysis and removes its censorship.
        setAudioMuted(false)
        session.continueStream()
        showStream()
    }

    func cancel() {
        // Conceal first, then detach analysis.
        blockStream()
        canReveal = false
        session?.cancel()
        session = nil
    }

    private func showStream() {
        videoView.isHidden = false
        redactionView.isHidden = true
    }

    private func obscureStream() {
        videoView.isHidden = true
        redactionView.isHidden = false
    }

    private func blockStream() {
        setAudioMuted(true)
        obscureStream()
    }
}
```

For an outgoing capture stream, use the capture-input initializer instead:

```swift
@available(iOS 26.0, *)
@MainActor
func makeOutgoingAnalyzer(
    participantID: String,
    captureDeviceInput: AVCaptureDeviceInput
) -> AppleSensitiveContentStreamAnalyzer {
    AppleSensitiveContentStreamAnalyzer(
        participantID: participantID,
        captureDeviceInput: captureDeviceInput
    )
}
```

## Treat the handler as the safety boundary

``SafeMediaStreamEngine/start(policy:applying:)`` calls `applying` on the main
actor and waits for the synchronous closure to return before continuing. Apply
every concealment, interruption, and audio change directly in that closure.
The session exposes lifecycle controls, not a second buffered event sequence,
which avoids mirroring analyzer events into an additional session buffer. The
analyzer's primary sequence can still buffer pending verdicts and must never use
a policy that evicts them.

Apple doesn't document `analysisChanges` as synchronously delivered or
main-actor isolated. For attached capture and decompression pipelines, Apple
censors frames after a detection. SafeMediaKit's fail-closed boundary is the
synchronous handler: it applies the host UI response before the engine takes
its next action.

The engine checks cancellation before applying every verdict because an async
stream can still contain buffered elements after its consumer is cancelled.
``SafeMediaStreamSession/cancel()`` ends analysis without producing a failure
decision. Use ``SafeMediaStreamSession/cancelAndWait()`` when teardown code must
wait for the monitoring task to exit. Conceal or stop the host pipeline before
either call because detaching Apple's analyzer can remove native censorship.

For decisions received after attachment, the engine automatically continues a
paused stream for `.allow` and `.muteAudio`. It keeps event consumption paused
for `.blur` and `.blurWithReveal` until the host calls
``SafeMediaStreamSession/continueStream()``. `.block` and `.interruptVideo` end
monitoring. Unavailability and setup-failure decisions finish immediately
because no analyzer is attached. If an attached analyzer throws or its event
sequence ends without host cancellation, the engine emits an `.analysisFailed`
decision before teardown so a revealed stream cannot silently continue
unmonitored.

Custom ``SafeMediaStreamAnalyzing`` implementations must pause or censor their
media pipeline before yielding a sensitive verdict and keep it protected until
`continueStream()` or `endAnalysis()`. Conceal or stop the host pipeline before
ending analysis. The main-actor handler closes the host UI boundary, but an
asynchronous sequence cannot retroactively protect frames rendered before its
event is consumed.

## Choose a live-video policy

``SafeMediaPolicy/streamSensitiveAction`` lets a policy use a live-video action
without changing its still-image or file-video behavior. A custom policy with a
`nil` stream action inherits `sensitiveAction`. The built-in presets use:

| Preset | Sensitive live video |
| --- | --- |
| `adultMinimal` | Allow and continue |
| `teenMessaging` | Blur with an app-controlled reveal path |
| `childStrict` | Interrupt the stream |
| `classroomStrict` | Interrupt the stream |

Unknown, unavailable, and failure events continue to use their existing policy
knobs. The Apple guidance in ``SafeMediaVerdict/guidance`` remains advisory and
separate from the primary policy action, so a host can also mute audio or show a
sensitivity indicator when appropriate.

## Never cache or transmit events

Live streams have no stable media identity. ``SafeMediaStreamEngine`` has no
cache or cache-key API. Every start that reaches preflight performs a fresh
availability check and, when analysis is available, a fresh attachment.

Apple's developer agreement prohibits transmitting information about whether
Sensitive Content Analysis flagged an image or video. Keep stream verdicts,
decisions, and guidance in the current process and on device. Do not send them
to analytics, remote logs, synced storage, or report payloads.
