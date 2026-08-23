import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus/locus.dart';
import 'package:locus/src/version.dart';

void main() {
  test('current package version surfaces match pubspec.yaml', () {
    final version = _pubspecVersion();

    expect(locusVersion, version);
    expect(Config.version, version);

    final config = File(
      'lib/src/config/geolocation_config.dart',
    ).readAsStringSync();
    expect(config, contains('static const String version = locusVersion;'));

    for (final path in [
      'bin/locus.dart',
      'bin/setup.dart',
      'bin/doctor.dart',
    ]) {
      final executable = File(path).readAsStringSync();
      expect(executable, contains("import 'package:locus/src/version.dart';"));
      expect(executable, isNot(contains('const _version =')));
    }

    final readme = File('README.md').readAsStringSync();
    expect(readme, contains('  locus: ^$version'));
    expect(readme, contains('- Current release: **v$version**'));
    expect(
      File('doc/guides/quickstart.md').readAsStringSync(),
      contains('  locus: ^$version'),
    );
    expect(
      File('doc/setup/installation.md').readAsStringSync(),
      contains('  locus: ^$version'),
    );

    final androidBuild = File('android/build.gradle.kts').readAsStringSync();
    expect(androidBuild, contains('file("../pubspec.yaml")'));

    final podspec = File('ios/locus.podspec').readAsStringSync();
    expect(
      podspec,
      contains("YAML.load_file(File.expand_path('../pubspec.yaml'"),
    );
    expect(podspec, contains("s.version          = pubspec['version']"));

    final exampleLock = File('example/pubspec.lock').readAsStringSync();
    expect(
      _lockPackageSection(exampleLock, 'locus'),
      contains('version: "$version"'),
    );
    expect(
      File('example/ios/Podfile.lock').readAsStringSync(),
      contains('- locus ($version):'),
    );

    final pipeline = File('.github/workflows/pipeline.yml').readAsStringSync();
    expect(pipeline, contains("grep '^version:' pubspec.yaml"));
  });

  test('sync tool updates every generated surface and fails closed', () async {
    final fixture = await Directory.systemTemp.createTemp(
      'locus-version-sync-',
    );
    addTearDown(() => fixture.delete(recursive: true));

    await _writeFixture(
      fixture,
      'pubspec.yaml',
      'name: locus\nversion: 9.8.7\n',
    );
    await _writeFixture(
      fixture,
      'lib/src/version.dart',
      "const String locusVersion = '0.0.0';\n",
    );
    await _writeFixture(
      fixture,
      'README.md',
      'dependencies:\n  locus: ^0.0.0\n\n- Current release: **v0.0.0**\n',
    );
    await _writeFixture(
      fixture,
      'doc/guides/quickstart.md',
      'dependencies:\n  locus: ^0.0.0\n',
    );
    await _writeFixture(
      fixture,
      'doc/setup/installation.md',
      'dependencies:\n  locus: ^0.0.0\n',
    );

    final script = File('tool/sync_version.dart').absolute.path;
    final stale = await _runSync(script, fixture, checkOnly: true);
    expect(stale.exitCode, 1);

    final updated = await _runSync(script, fixture);
    expect(updated.exitCode, 0, reason: '${updated.stdout}\n${updated.stderr}');
    expect(
      File('${fixture.path}/lib/src/version.dart').readAsStringSync(),
      contains("locusVersion = '9.8.7'"),
    );
    expect(
      File('${fixture.path}/README.md').readAsStringSync(),
      allOf(contains('locus: ^9.8.7'), contains('release: **v9.8.7**')),
    );

    final clean = await _runSync(script, fixture, checkOnly: true);
    expect(clean.exitCode, 0, reason: '${clean.stdout}\n${clean.stderr}');

    await File('${fixture.path}/doc/setup/installation.md').delete();
    final missing = await _runSync(script, fixture, checkOnly: true);
    expect(missing.exitCode, 2);
    expect(missing.stderr, contains('version sync incomplete'));
  });
}

String _pubspecVersion() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  return RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec)!.group(1)!;
}

String _lockPackageSection(String lockfile, String packageName) {
  final section = RegExp(
    '^  ${RegExp.escape(packageName)}:\\n(?:    .*\\n?)*',
    multiLine: true,
  ).firstMatch(lockfile);
  expect(
    section,
    isNotNull,
    reason: '$packageName is absent from pubspec.lock',
  );
  return section!.group(0)!;
}

Future<void> _writeFixture(
  Directory root,
  String relativePath,
  String content,
) async {
  final file = File('${root.path}/$relativePath');
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

Future<ProcessResult> _runSync(
  String script,
  Directory workingDirectory, {
  bool checkOnly = false,
}) {
  return Process.run('dart', [
    script,
    if (checkOnly) '--check',
  ], workingDirectory: workingDirectory.path);
}
