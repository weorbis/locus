# Security Policy

## Supported Versions

Security fixes ship in the latest 2.x release. Upgrade to it to receive them.

| Version             | Supported |
| :------------------ | :-------- |
| Latest 2.x release  | Yes       |
| Older 2.x releases  | No        |
| 1.x and earlier     | No        |

## Reporting a Vulnerability

We value the security of our users. If you discover a potential security vulnerability in Locus, please report it responsibly.

### How to Report

1. **Do not** open a public issue for security-related findings.
2. Report it privately through [GitHub private vulnerability reporting](https://github.com/weorbis/locus/security/advisories/new). If you cannot use GitHub, email **info@weorbis.com**.
3. Include as much detail as possible to help us reproduce and resolve the issue:
   - Vulnerability description
   - Reproduction steps
   - Potential impact

### Assessment Process

- **Acknowledgment**: You will receive an acknowledgment of your report within 48 hours.
- **Resolution**: Critical vulnerabilities are prioritized, with a goal of releasing a fix within 14 days.
- **Disclosure**: We will coordinate with you on the timing of a public disclosure.

## Security Best Practices

To ensure the security of your users when using Locus:

1. **HTTPS**: Use secure HTTPS endpoints for all location synchronization.
2. **Minimal Permissions**: Only request the permissions necessary for your specific use case.
3. **Logging**: Ensure that verbose logging is disabled in production environments.
4. **Privacy**: Comply with relevant data privacy regulations (GDPR, CCPA) when handling location data.

## Location Data Security

### Server-Side

- Enforce HTTPS for all ingestion endpoints.
- Encrypt location data at rest and restrict access by role.
- Implement request authentication (e.g., OAuth2 bearer tokens or signed keys).
- Log access for auditability and set retention policies for deletion.

### Client-Side

- Locations are queued in SQLite; prefer encrypted storage where available.
- **Important**: Do not store authentication tokens or API keys in SharedPreferences unencrypted.
  - Use flutter_secure_storage or platform-specific secure storage (Keychain on iOS, Keystore on Android).
  - When using `setHeadersCallback` or `setSyncBodyBuilder`, retrieve credentials from secure storage.
- Do not start tracking before user consent; allow opt-out.
- Keep foreground notifications visible on Android when tracking.
- Avoid logging raw coordinates in production logs.
- Consider enabling SSL pinning in production using `sslPinningCertificate` (Android) or `sslPinningFingerprints` (iOS).

## Vulnerability Scanning

We maintain security through continuous monitoring:

### Automated Scanning

- **Dependabot alerts and security updates**: Dependencies are checked against the GitHub Advisory Database, and fixes are proposed automatically.
- **CodeQL**: Kotlin, Swift, and workflow code is scanned on every pull request and push to `main`.
- **Secret scanning with push protection**: Pushes that contain known credential formats are blocked.
- **Flutter analyze**: Static analysis runs on every pull request.

### Manual Review

- **Code review**: Every change to `main` requires an approving review.

### For Contributors

Before submitting changes:

```bash
# Run security analysis
flutter analyze

# Check for outdated packages with known vulnerabilities
flutter pub outdated

# Run all tests including security-related tests
flutter test
```

Report any security concerns following the process outlined in "Reporting a Vulnerability" above.
