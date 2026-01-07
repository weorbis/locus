# Security Policy

## Supported Versions

We provide security updates for the following versions of Locus:

| Version | Supported | Notes |
| :------ | :-------- | :---- |
| 1.x.x   | Yes       | Current stable release |
| 2.0.x   | No        | Unreleased (work in progress) |

## Reporting a Vulnerability

We value the security of our users. If you discover a potential security vulnerability in Locus, please report it responsibly.

### How to Report

1. **Do not** open a public issue for security-related findings.
2. Email your report to **security@mkoksal.dev**.
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
- Do not start tracking before user consent; allow opt-out.
- Keep foreground notifications visible on Android when tracking.
- Avoid logging raw coordinates in production logs.

## Vulnerability Scanning

We maintain security through continuous monitoring:

### Automated Scanning

- **Dependency auditing**: All dependencies are regularly scanned for known vulnerabilities.
- **CI/CD integration**: Security checks are integrated into our continuous integration pipeline.
- **GitHub Dependabot**: Automated dependency updates with security patches.
- **Flutter analyze**: Static analysis runs on every commit to catch potential issues.

### Manual Review

- **Code review**: All changes undergo security-focused code review.
- **Third-party audit**: Critical releases undergo external security audits.
- **Penetration testing**: Regular testing of network communication and data storage.

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
