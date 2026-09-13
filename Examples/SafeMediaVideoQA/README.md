# SafeMediaVideoQA

A small, user-operated iOS 26+ device harness for
`AppleSensitiveContentStreamAnalyzer`. It attaches the real capture input or
VideoToolbox decompression session. It uses the adapter directly so each event
conceals the preview until an explicit Resume. It is a QA tool, not a production
policy/overlay example; see the package's live-video integration guide for that.

Camera and playback start only after tapping **Start / repeat**. There is no
microphone input, recording output, networking, verdict logging, analytics, or
result persistence. Keep intervention details, images, and timing observations
on the test device. Do not capture/upload the screen or debugger logs during a
media test. Backgrounding the app conceals the preview and stops the pipeline.

## Build

From this directory, using XcodeGen and the installed Xcode:

```sh
xcodegen generate --spec project.yml
xcodebuild -quiet -project SafeMediaVideoQA.xcodeproj -scheme SafeMediaVideoQA \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/simulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project SafeMediaVideoQA.xcodeproj -scheme SafeMediaVideoQA \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath .build/device CODE_SIGNING_ALLOWED=NO build
```

The only package dependency is the local `../..` SafeMediaKit checkout.
Generated projects and build products are ignored. For another installed Xcode,
prefix the build command with `DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer`.

Real-device signing requires an existing development profile with the Sensitive
Content Analysis entitlement (`analysis` array value). Choose your own team and
bundle identifier in Xcode or supply build overrides. Do not enable provisioning
updates or alter account settings as part of a passive readiness check.

With an existing Xcode-managed profile, use local signing overrides:

```sh
xcodebuild -quiet -project SafeMediaVideoQA.xcodeproj -scheme SafeMediaVideoQA \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath .build/signed \
  PRODUCT_BUNDLE_IDENTIFIER=YOUR_EXISTING_QA_BUNDLE_ID \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID CODE_SIGN_STYLE=Automatic build
```

The verification run reused an installed profile without
`-allowProvisioningUpdates`. A manual-signing override rejected that profile
because it was Xcode-managed.

For a passive device check, launch with `--qa-policy-preflight`. This prints only
whether system analysis policy is enabled, then exits successfully before
creating a source or UI. Normal launches print no app diagnostics. Do not attach
console logging while performing media tests.

```sh
xcrun devicectl device process launch --device YOUR_DEVICE_ID \
  --terminate-existing --console YOUR_EXISTING_QA_BUNDLE_ID --qa-policy-preflight
```

`--qa-decode-attachment-smoke` is a separate lifecycle diagnostic. It loads only
the compressed format metadata from the bundled 64 × 64 solid-gray H.264 clip,
constructs a VT session, and attempts ten availability/start/end cycles with one
participant ID, startup cancellation, and a restart after cancellation. It never
starts the asset reader, submits/decodes a frame, iterates verdicts, or creates
camera/microphone inputs. It exposes no media controls and exits with only
lifecycle PASS/FAIL output. A cancellation scheduling miss reports INCONCLUSIVE
with a nonzero exit code, because `Task.yield()` cannot guarantee that
cancellation lands inside startup suspension. A successful cancellation probe
proves cancellation was observed, not the exact internal suspension point or
coverage of every cancellation point.

```sh
xcrun devicectl device process launch --device YOUR_DEVICE_ID \
  --terminate-existing --console YOUR_EXISTING_QA_BUNDLE_ID --qa-decode-attachment-smoke
```

The 1,563-byte synthetic fixture was generated locally, without external media:

```sh
ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=gray:s=64x64:r=1:d=1 \
  -an -c:v libx264 -pix_fmt yuv420p -frames:v 1 -movflags +faststart Resources/solid-gray.mp4
```

## Device procedure

Apple provides a non-explicit QR image, test video, and development test profile
in [Testing your app's response to sensitive media](https://developer.apple.com/documentation/sensitivecontentanalysis/testing-your-app-s-response-to-sensitive-media).
The profile requires installation and reboot. Its documented examples cover
image and file-video analysis; do not assume the same marker demonstrates live
stream detection until observed on the target OS. Have the device owner handle
profile installation and settings changes separately.

1. Launch and tap **Check policy**. This does not request camera access.
   Enabled policy is only preflight; a signed attachment can still fail.
2. After the device owner approves camera access, select **Camera** and tap
   **Start / repeat**. Point at an approved, non-explicit test scene. Confirm
   the local attachment status and preview. Nothing uses the microphone.
3. For incoming video, use **Choose local video** to select a local, compressed
   H.264/HEVC test clip, then Start. The clip is read through `AVAssetReader`
   without decoding, submitted to the attached `VTDecompressionSession`, and
   displayed from that session's output. There is no alternate player path.
   Audio tracks are not read. End-of-file stops and conceals playback; Start
   creates a fresh reader at the beginning.
4. Start/Stop each source repeatedly (suggested: 10 cycles). The same
   call-scoped participant UUID is reused across both source modes and repeats;
   **New participant** stops playback and replaces it. This does not exercise
   two simultaneous streams for one participant.
5. Enable **Probe startup cancellation**, then Start. The probe schedules
   cancellation around the adapter's suspension and reports locally whether
   cancellation occurred. Scheduling cannot prove every internal cancellation
   point. Also exercise Start followed by Stop and immediate Start, including
   while camera permission or asset loading is pending. Confirm no later
   preview appears for the cancelled generation.
6. With owner-approved Apple test media/profile, check concealment and explicit
   Resume on both sources, then repeat. Stop and background while concealed.
   Host concealment does not by itself verify Apple's native capture
   interruption or blank decoded frames: those remain separate native-pipeline
   observations. Do not mark native censorship verified from this overlay alone.
7. Attachment duration is displayed locally. **Mark stimulus** measures a manual
   marker-to-handler interval, including operator delay; it is not per-frame
   classifier latency or a benchmark. Do not export these media-linked results.

All source setup/teardown and pending-frame generations are coordinated by the
main-actor controller. Capture start/stop is enqueued on that actor, then runs
serially off it. Decoder input is paced by decode timestamps and output by
presentation timestamps. EOF awaits pending presentations and their durations.
Concealment, Resume, and Stop discard queued presentations. This simple file
decoder is for small QA clips, not performance or production playback evaluation.

The UIKit QA test host also runs decoder regressions using the synthetic gray
fixtures, without an analyzer or sensors. The second fixture is a two-second
luminance ramp with B-frames, generated with:

```sh
ffmpeg -hide_banner -loglevel error -f lavfi \
  -i 'nullsrc=s=64x64:r=5:d=2,geq=lum=16+N*20:cb=128:cr=128' \
  -an -c:v libx264 -pix_fmt yuv420p \
  -x264-params 'bframes=2:b-adapt=0:keyint=30:scenecut=0' \
  -movflags +faststart Resources/gray-ramp-bframes.mp4
```

## Verification log — 2026-09-12

| Check | Result |
| --- | --- |
| Xcode 26.6 / iOS 26.5 SDK, unsigned device build | Passed |
| Xcode 26.6 / simulator SDK, arm64 and x86_64 build | Passed |
| Xcode 27 beta / iOS 27 SDK, unsigned device build | Passed |
| Existing-profile signed device build | Passed; signature contains SCA `analysis` entitlement |
| Paired iPhone 17 Pro Max, iOS 26.3 | Booted, unlocked, Developer Mode enabled |
| Device installation and stopped launch | Confirmed by `devicectl` |
| System policy on physical device | Enabled; passive diagnostic exited 0, without creating media sources |
| Simulator shell | Visually checked stopped; cover visible, controls visible, Resume disabled |
| No-frame VT lifecycle diagnostic | Built on both toolchains and installed; execution blocked by locked device (CoreDeviceError 10002; FBSOpenApplicationErrorDomain 7) |
| Capture/decode attachment on physical device | Not yet exercised |
| Physical-device cancellation, repeats, native censorship/resume, latency | Not yet exercised |
| Camera, microphone, test profile, system settings | No camera/microphone activated; no profile or settings changed |

Build and launch success establish harness readiness only. Hardware behavior
remains an open validation gate until the device owner unlocks and operates the
test. The earlier normal stopped launch and policy preflight succeeded while
unlocked; the later diagnostic launch was rejected before the app ran.

### Fresh-eyes review — 2026-09-13

- Fixed compressed-reader marker buffers being submitted as frames, EOF
  overtaking frame presentation, B-frame display ordering, and cold-start clock
  timing. Added single-frame duration, B-frame order, and Stop-cancellation
  regressions to the existing UIKit QA host: all 14 hosted tests pass on iOS
  26.0.1 and 27.0 (11 overlay tests plus 3 decoder tests).
- Capture lifecycle calls now enqueue on the main actor before suspension,
  preserving Start/Stop order while the capture queue performs blocking work.
- Resume drops pending presentations, and the controls now live in a vertical
  scroll view for short/landscape layouts. The stopped app was launched and
  inspected in landscape; automated gesture delivery did not confirm scrolling,
  so manual scroll interaction remains unverified.
- Updated unsigned device builds pass on both installed Xcode toolchains;
  final build/test logs contain no compiler warnings. No real camera, microphone,
  analyzer media test, signing/profile change, or physical-device launch was
  performed during this review. Hardware validation remains open.
