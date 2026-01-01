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

## Reporting Issues

When reporting an issue, please provide:

- Your environment details (`flutter doctor`).
- The specific device and OS version being used.
- A clear description of the problem and steps to reproduce.
- Any relevant logs or stack traces.
