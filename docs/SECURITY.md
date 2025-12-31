# Security Policy

## Supported Versions

We release patches for security vulnerabilities in the following versions:

| Version | Supported          |
| ------- | ------------------ |
| 2.x.x   | :white_check_mark: |
| 1.x.x   | :x:                |

## Reporting a Vulnerability

We take the security of `locus` seriously. If you discover a security vulnerability, please report it responsibly.

### How to Report

1. **Do not** open a public GitHub issue for security vulnerabilities.
2. Email your findings to **security@locus.com** (or create a private security advisory on GitHub).
3. Include as much detail as possible:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

### What to Expect

- **Acknowledgment**: We will acknowledge your report within 48 hours.
- **Investigation**: We will investigate and validate the vulnerability.
- **Resolution**: We aim to release a fix within 14 days for critical issues.
- **Disclosure**: We will coordinate with you on public disclosure timing.

### Scope

The following are in scope for security reports:

- The `locus` Flutter plugin
- Native Android (Java/Kotlin) code in `/android`
- Native iOS (Swift/Objective-C) code in `/ios`
- Example application vulnerabilities that could affect end users

### Out of Scope

- Third-party dependencies (report directly to maintainers)
- Issues in applications that use this plugin (report to application maintainers)
- Social engineering attacks

## Security Best Practices

When using this plugin, we recommend:

1. **Permissions**: Only request location permissions when necessary and explain why.
2. **Data Handling**: Handle location data according to privacy regulations (GDPR, CCPA).
3. **HTTP Sync**: Use HTTPS endpoints for all location data transmission.
4. **Logging**: Disable verbose logging in production builds.

Thank you for helping keep `locus` and its users safe!
