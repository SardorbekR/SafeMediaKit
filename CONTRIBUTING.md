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

To build against a different Xcode toolchain (for example, to work on future `detectedTypes` category mapping) without changing global Xcode selection:

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
