# Contributing to Locus

Thank you for your interest in contributing to Locus. We welcome contributions from the community to help improve the SDK.

## Development Environment

1. Ensure you have the Flutter SDK (stable channel) installed.
2. Clone the repository and fetch dependencies:
   ```bash
   flutter pub get
   ```
3. Run the analysis and suite of tests to verify your environment:
   ```bash
   flutter analyze
   flutter test
   ```

## Repository Structure

- `lib/` – Core SDK logic, configuration, and models.
- `android/` – Native Android implementation (Java).
- `ios/` – Native iOS implementation (Swift).
- `example/` – Demonstration application.
- `test/` – Comprehensive unit and integration tests.

## Contribution Guidelines

- **Focused Changes**: Keep pull requests focused on a single feature or bug fix.
- **Testing**: Include tests for any new functionality or bug fixes. Ensure all existing tests pass.
- **Documentation**: Update the README or inline comments if your changes affect the public API.
- **Linting**: Adhere to the project's linting rules defined in `analysis_options.yaml`.

## Code Style

### Dart & Flutter
- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart) and run `dart format` before submitting.
- Keep lines at or under 100 characters where practical.
- Prefer named parameters for readability; avoid positional booleans.
- Public APIs must include doc comments; reference related types with `[]`.
- Avoid `print`; use structured logging utilities.

### Naming
- Classes/types: PascalCase (`LocusLocation`).
- Methods/fields: camelCase (`getCurrentPosition`).
- Private members: underscore prefix (`_state`).
- Constants: camelCase (`maxGeofences`).

### Commits and PRs
- Use Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`).
- Example: `fix(privacy): align geofence removal return type`.
- PRs should summarize changes, list tests run, and link issues.

### Tests
- Add or update tests alongside code changes.
- Cancel stream subscriptions in tearDown to avoid leaks.
- Prefer async helpers and matchers from `test/helpers` and `MockLocus` for services.

### Managing Dependencies

When adding or updating dependencies:

- **Justify new dependencies**: Explain why a new dependency is necessary and consider alternatives.
- **Version constraints**: Use caret syntax (^) for compatible version ranges to allow patch and minor updates.
- **Security**: Verify dependencies are actively maintained and have no known vulnerabilities.
- **License compatibility**: Ensure dependency licenses are compatible with this project's license.
- **Minimize dependencies**: Prefer Dart/Flutter built-in solutions when possible.
- **Native dependencies**: Document any native iOS/Android dependency requirements in platform-specific files.
- **Update regularly**: Keep dependencies up-to-date, especially for security patches.
- **Testing**: Run the full test suite after dependency changes to ensure compatibility.

## Reporting Issues

When reporting an issue, please provide:

- Your environment details (`flutter doctor`).
- The specific device and OS version being used.
- A clear description of the problem and steps to reproduce.
- Any relevant logs or stack traces.
