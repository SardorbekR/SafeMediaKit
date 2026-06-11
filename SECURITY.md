# Security Policy

## Reporting Vulnerabilities

Please report security issues privately through GitHub Security Advisories: use "Report a vulnerability" on this repository's Security tab. Private vulnerability reporting is enabled.

Do not open public issues for vulnerabilities and do not attach explicit media to GitHub issues or pull requests.

## Media Handling

SafeMediaKit processes host-app-provided media locally through Apple's public APIs. It does not upload media, include telemetry, or log media URLs by default.

## Reproductions

Use one of these approaches for security or behavior reproductions:

- `MockSafeMediaAnalyzer` from `SafeMediaKitTesting`
- Apple's official QR-code/profile testing flow for Sensitive Content Analysis
- Safe, non-explicit placeholder media

Do not submit real explicit media as a reproduction artifact.
