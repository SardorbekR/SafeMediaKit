# UIKit overlay QA

A simulator-only gallery and app host for `SafeMediaImageViewTests`. It uses
generated teal placeholders and mock verdicts; no entitlements, explicit media,
camera, or network are needed. Use the gallery to inspect Show/Report,
VoiceOver, and Settings > Accessibility > Display & Text Size > Larger Text.

Open `SafeMediaUIKitQA.xcodeproj`, or run from the repository root:

```sh
xcodebuild test \
  -project Examples/SafeMediaUIKitQA/SafeMediaUIKitQA.xcodeproj \
  -scheme SafeMediaUIKitQA \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

The overlay test source remains in the package's existing test directory. An app
host is needed for control action dispatch; hostless package tests cannot prove
those interactions. Mock overlays rendered with `CALayer.render(in:)` are
attached to the test result. Tests inspect accessibility structure; listening
to VoiceOver remains a manual check.

This host also runs `Tests/DecodePipelineTests.swift` against the video QA
example's decoder source and synthetic gray clips. These check frame delivery,
display ordering, duration, and cancellation without constructing an analyzer
or accessing sensors. They do not verify Apple's sensitive-media detection.

The project is checked in so Xcode alone can run it. If its structure changes,
regenerate with the optional XcodeGen development tool:

```sh
xcodegen generate --spec Examples/SafeMediaUIKitQA/project.yml
```
