# Contributing

Thanks for your interest in contributing!

## Development setup

1. Install Flutter (stable channel).
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. Run lint and tests:
   ```bash
   flutter analyze
   flutter test
   ```

## Repository layout

- `lib/src/` – Dart API, models, and config.
- `android/` – Android native implementation.
- `ios/` – iOS native implementation.
- `example/` – Demo app.
- `test/` – Unit tests.

## Pull requests

- Keep changes focused and scoped.
- Update or add tests for new behavior.
- Run `flutter analyze` and `flutter test` before submitting.
- Update `README.md` if public API changes.

## Coding style

- Follow `flutter_lints` rules (see `analysis_options.yaml`).
- Prefer clear naming and small focused methods.

## Reporting issues

Please include:
- Flutter version (`flutter --version`)
- Device/OS (Android/iOS version)
- Steps to reproduce
- Logs and stack traces (if applicable)
