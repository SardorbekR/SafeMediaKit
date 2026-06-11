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
