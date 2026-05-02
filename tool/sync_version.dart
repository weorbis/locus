// Propagates pubspec.yaml's `version:` to the Dart constants the SDK
// exposes to host apps and CLI tools.
//
// Native build files (android/build.gradle.kts, ios/locus.podspec) read
// pubspec.yaml directly at build time, so they're not listed here. CI
// reads pubspec.yaml directly for the tag check.
//
// Run from the repo root:
//   dart run tool/sync_version.dart           — write changes
//   dart run tool/sync_version.dart --check   — exit non-zero if anything
//                                               is stale (CI use)

import 'dart:io';

void main(List<String> args) {
  final checkOnly = args.contains('--check');

  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('pubspec.yaml not found. Run from the repo root.');
    exit(2);
  }

  final version = _parseVersion(pubspec.readAsStringSync());
  if (version == null) {
    stderr.writeln('Could not find a "version:" line in pubspec.yaml.');
    exit(2);
  }

  // Each target is a (path, regex-with-2-capturing-groups). The version
  // string sits between the two captures. Updating preserves whatever
  // prefix/suffix surrounds it (single quotes, spaces, etc.) so the file
  // diff stays minimal and readable.
  final targets = <_Target>[
    _Target.line(
      path: 'lib/src/config/geolocation_config.dart',
      pattern: RegExp(r"(static const String version = ')([^']+)(';)"),
    ),
    _Target.line(
      path: 'bin/doctor.dart',
      pattern: RegExp(r"(const _version = ')([^']+)(';)"),
    ),
    _Target.line(
      path: 'bin/setup.dart',
      pattern: RegExp(r"(const _version = ')([^']+)(';)"),
    ),
    _Target.line(
      path: 'bin/locus.dart',
      pattern: RegExp(r"(const _version = ')([^']+)(';)"),
    ),
  ];

  var stale = 0;
  var written = 0;
  for (final target in targets) {
    final result = target.apply(version, checkOnly: checkOnly);
    switch (result) {
      case _Outcome.upToDate:
        // Quiet: only chatter when something actually moves.
        break;
      case _Outcome.staleInCheck:
        stderr.writeln('  stale: ${target.path}');
        stale++;
      case _Outcome.updated:
        stdout.writeln('  updated: ${target.path}');
        written++;
      case _Outcome.missing:
        stderr.writeln('  missing: ${target.path} (skipped)');
    }
  }

  if (checkOnly) {
    if (stale > 0) {
      stderr.writeln('$stale file(s) out of sync with pubspec ($version). '
          'Run `dart run tool/sync_version.dart` to fix.');
      exit(1);
    }
    stdout.writeln('all version pins in sync at $version');
    return;
  }

  stdout.writeln(written == 0
      ? 'all version pins already at $version'
      : 'synced $written file(s) to $version');
}

String? _parseVersion(String pubspecContent) {
  final match =
      RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(pubspecContent);
  return match?.group(1)?.trim();
}

class _Target {
  _Target.line({required this.path, required this.pattern});

  final String path;

  /// Three capturing groups: (prefix)(version)(suffix). The version capture
  /// is what we replace; prefix/suffix are preserved verbatim so the file's
  /// formatting stays untouched.
  final RegExp pattern;

  _Outcome apply(String desired, {required bool checkOnly}) {
    final file = File(path);
    if (!file.existsSync()) return _Outcome.missing;

    final content = file.readAsStringSync();
    final match = pattern.firstMatch(content);
    if (match == null) {
      stderr.writeln('  no match in $path for ${pattern.pattern}');
      return _Outcome.missing;
    }

    final current = match.group(2)!;
    if (current == desired) return _Outcome.upToDate;
    if (checkOnly) return _Outcome.staleInCheck;

    final updated = content.replaceFirst(
      pattern,
      '${match.group(1)}$desired${match.group(3)}',
    );
    file.writeAsStringSync(updated);
    return _Outcome.updated;
  }
}

enum _Outcome { upToDate, updated, staleInCheck, missing }
