# Contributing

Thanks for helping improve SafeMediaKit.

## Ground Rules

- Do not commit explicit media fixtures.
- Do not add private APIs, undocumented Settings URLs, screen scraping, or system-wide filtering claims.
- Keep media processing local.
- Keep public API changes documented in `README.md` and `CHANGELOG.md`.
- Add or update tests for policy, cache, and decision-engine behavior.

## Development

```sh
swift build
swift test
```

To validate Xcode 27 category mapping without changing global Xcode selection:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
```

UIKit tests must run on an iOS simulator; macOS `swift test` excludes UIKit.
Choose an available simulator from `xcrun simctl list devices available`:

```sh
xcodebuild test \
  -project Examples/SafeMediaUIKitQA/SafeMediaUIKitQA.xcodeproj \
  -scheme SafeMediaUIKitQA \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

Use the UIKit QA app host to exercise button dispatch and rendering. The
hostless `SafeMediaKit-Package` scheme can run core iOS tests, but does not
initialize `UIApplication` for UIKit interactions. The overlay tests keep
rendered attachments in the Xcode test result for visual inspection.
The same host runs the video QA decoder's synthetic-fixture regressions without
an analyzer or sensor access; these are not real-device SCA validation.

## Pull Requests

Before opening a PR:

- `swift build` passes.
- `swift test` passes.
- README caveats remain accurate.
- No explicit content is committed.
- No App Store-unsafe claims are introduced.

## Manual QA Checklist

For changes touching `SafeMediaImage` or `SafeMediaImageView`, verify by hand
(simulator or device, mock analyzer is fine):

- [ ] Sensitive image shows blur with the warning overlay.
- [ ] The image never appears, even briefly, before the decision on first scan.
- [ ] Reveal shows the image; Report fires the callback.
- [ ] Switching the URL mid-scan never shows the previous image or decision.
- [ ] Unavailable analysis shows the unavailable copy and does not crash.
- [ ] Blocked state shows the blocked placeholder without a reveal button.
- [ ] VoiceOver reads the warning title/message and both buttons; the blurred
      image is not exposed as content.
- [ ] Dynamic Type at large sizes keeps the overlay readable.
