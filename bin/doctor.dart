/// Locus CLI - Doctor Command
///
/// Diagnoses Locus configuration and platform setup issues.
///
/// Usage:
///   `dart run locus:doctor [options]`
///
/// Options:
///   --fix    Attempt to automatically fix issues
///   -h, --help    Show this help message

library;

import 'dart:io';

import 'package:args/args.dart';

const _version = '2.0.0';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('fix', defaultsTo: false, help: 'Attempt to fix issues')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help');

  ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    stdout.writeln('Error: $e');
    stdout.writeln('Usage: dart run locus:doctor [options]');
    stdout.writeln(parser.usage);
    exit(1);
  }

  if (results['help'] as bool) {
    stdout.writeln('Locus Doctor v$_version');
    stdout.writeln('');
    stdout.writeln('Diagnoses Locus configuration and platform setup issues.');
    stdout.writeln('');
    stdout.writeln('Usage: dart run locus:doctor [options]');
    stdout.writeln('');
    stdout.writeln(parser.usage);
    exit(0);
  }

  final shouldFix = results['fix'] as bool;

  stdout.writeln('''
╔══════════════════════════════════════════════════════════════╗
║                      Locus - Doctor                           ║
╠══════════════════════════════════════════════════════════════╣
''');

  var issueCount = 0;
  var fixedCount = 0;

  // Check Android configuration
  final androidIssues = await _checkAndroid(shouldFix);
  issueCount += androidIssues.$1;
  fixedCount += androidIssues.$2;

  // Check iOS configuration
  final iosIssues = await _checkIos(shouldFix);
  issueCount += iosIssues.$1;
  fixedCount += iosIssues.$2;

  // Check package configuration
  await _checkPackage();

  // Summary
  stdout.writeln(
      '║                                                               ║');
  stdout.writeln(
      '║  ────────────────────────────────────────────────────────────║');

  if (issueCount == 0) {
    stdout.writeln(
        '║  ✅ All checks passed! Your project is ready.                 ║');
  } else if (shouldFix && fixedCount > 0) {
    stdout.writeln(
        '║  🔧 Fixed $fixedCount issue(s). ${issueCount - fixedCount} remaining.                          ║');
  } else {
    stdout.writeln(
        '║  ⚠️  Found $issueCount issue(s). Run with --fix to auto-repair.      ║');
  }

  stdout.writeln(
      '║                                                               ║');
  stdout.writeln(
      '╚══════════════════════════════════════════════════════════════╝');

  exit(issueCount > fixedCount ? 1 : 0);
}

Future<(int, int)> _checkAndroid(bool shouldFix) async {
  stdout.writeln(
      '║                                                               ║');
  stdout.writeln(
      '║  Checking Android configuration...                            ║');

  var issues = 0;
  var fixed = 0;

  const manifestPath = 'android/app/src/main/AndroidManifest.xml';
  final manifestFile = File(manifestPath);

  if (!manifestFile.existsSync()) {
    _printCheck('AndroidManifest.xml', false, 'File not found');
    return (1, 0);
  }

  _printCheck('AndroidManifest.xml found', true);

  var content = manifestFile.readAsStringSync();
  var modified = false;

  // Required permissions
  final requiredPermissions = [
    ('ACCESS_FINE_LOCATION', 'android.permission.ACCESS_FINE_LOCATION'),
    ('ACCESS_COARSE_LOCATION', 'android.permission.ACCESS_COARSE_LOCATION'),
    (
      'ACCESS_BACKGROUND_LOCATION',
      'android.permission.ACCESS_BACKGROUND_LOCATION'
    ),
    ('FOREGROUND_SERVICE', 'android.permission.FOREGROUND_SERVICE'),
    (
      'FOREGROUND_SERVICE_LOCATION',
      'android.permission.FOREGROUND_SERVICE_LOCATION'
    ),
    ('ACTIVITY_RECOGNITION', 'android.permission.ACTIVITY_RECOGNITION'),
  ];

  for (final (name, permission) in requiredPermissions) {
    if (content.contains(permission)) {
      _printCheck('$name permission', true);
    } else {
      _printCheck('$name permission', false, 'Missing');
      issues++;

      if (shouldFix) {
        final insertPoint = content.lastIndexOf('</manifest>');
        if (insertPoint != -1) {
          final permissionTag =
              '    <uses-permission android:name="$permission" />\n';
          content = content.substring(0, insertPoint) +
              permissionTag +
              content.substring(insertPoint);
          modified = true;
          fixed++;
          _printFix('Added $name permission');
        }
      }
    }
  }

  if (modified) {
    manifestFile.writeAsStringSync(content);
  }

  // Check minSdkVersion
  final minSdkResult = await _checkMinSdkVersion();
  if (!minSdkResult) {
    issues++;
  }

  return (issues, fixed);
}

Future<bool> _checkMinSdkVersion() async {
  const gradlePath = 'android/app/build.gradle';
  const gradleKtsPath = 'android/app/build.gradle.kts';

  File? gradleFile;
  if (File(gradleKtsPath).existsSync()) {
    gradleFile = File(gradleKtsPath);
  } else if (File(gradlePath).existsSync()) {
    gradleFile = File(gradlePath);
  }

  if (gradleFile == null) {
    _printCheck('build.gradle', false, 'Not found');
    return false;
  }

  final content = gradleFile.readAsStringSync();

  // Check for Flutter's default (which uses flutter.minSdkVersion)
  if (content.contains('flutter.minSdkVersion') ||
      content.contains('minSdkVersion.get()')) {
    _printCheck('minSdkVersion (Flutter default)', true);
    return true;
  }

  // Try to parse explicit value
  final patterns = [
    RegExp(r'minSdkVersion\s*[=:]\s*(\d+)'),
    RegExp(r'minSdk\s*[=:]\s*(\d+)'),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(content);
    if (match != null) {
      final minSdk = int.tryParse(match.group(1) ?? '') ?? 0;
      if (minSdk >= 26) {
        _printCheck('minSdkVersion is $minSdk (required: >= 26)', true);
        return true;
      } else {
        _printCheck('minSdkVersion is $minSdk', false, 'Needs >= 26');
        return false;
      }
    }
  }

  _printCheck('minSdkVersion >= 26', true, 'Assumed from Flutter');
  return true;
}

Future<(int, int)> _checkIos(bool shouldFix) async {
  stdout.writeln(
      '║                                                               ║');
  stdout.writeln(
      '║  Checking iOS configuration...                                ║');

  var issues = 0;
  var fixed = 0;

  const plistPath = 'ios/Runner/Info.plist';
  final plistFile = File(plistPath);

  if (!plistFile.existsSync()) {
    _printCheck('Info.plist', false, 'File not found');
    return (1, 0);
  }

  _printCheck('Info.plist found', true);

  var content = plistFile.readAsStringSync();
  var modified = false;

  // Required keys
  final requiredKeys = [
    ('NSLocationWhenInUseUsageDescription', 'This app needs location access.'),
    (
      'NSLocationAlwaysAndWhenInUseUsageDescription',
      'This app needs background location.'
    ),
    ('NSMotionUsageDescription', 'This app uses motion to detect activity.'),
  ];

  for (final (key, defaultValue) in requiredKeys) {
    if (content.contains('<key>$key</key>')) {
      _printCheck(key, true);
    } else {
      _printCheck(key, false, 'Missing');
      issues++;

      if (shouldFix) {
        final insertPoint = content.lastIndexOf('</dict>');
        if (insertPoint != -1) {
          final keyValue = '''
\t<key>$key</key>
\t<string>$defaultValue</string>
''';
          content = content.substring(0, insertPoint) +
              keyValue +
              content.substring(insertPoint);
          modified = true;
          fixed++;
          _printFix('Added $key');
        }
      }
    }
  }

  // Check UIBackgroundModes
  if (content.contains('<string>location</string>')) {
    _printCheck("UIBackgroundModes includes 'location'", true);
  } else {
    _printCheck("UIBackgroundModes includes 'location'", false, 'Missing');
    issues++;

    if (shouldFix) {
      if (content.contains('<key>UIBackgroundModes</key>')) {
        final arrayStart =
            content.indexOf('<array>', content.indexOf('UIBackgroundModes'));
        if (arrayStart != -1) {
          final insertPoint = arrayStart + '<array>'.length;
          content =
              '${content.substring(0, insertPoint)}\n\t\t<string>location</string>${content.substring(insertPoint)}';
          modified = true;
          fixed++;
          _printFix('Added location to UIBackgroundModes');
        }
      } else {
        final insertPoint = content.lastIndexOf('</dict>');
        if (insertPoint != -1) {
          const bgModes = '''
\t<key>UIBackgroundModes</key>
\t<array>
\t\t<string>location</string>
\t</array>
''';
          content = content.substring(0, insertPoint) +
              bgModes +
              content.substring(insertPoint);
          modified = true;
          fixed++;
          _printFix('Added UIBackgroundModes with location');
        }
      }
    }
  }

  if (modified) {
    plistFile.writeAsStringSync(content);
  }

  // Check iOS deployment target
  await _checkIosDeploymentTarget();

  return (issues, fixed);
}

Future<void> _checkIosDeploymentTarget() async {
  const podfilePath = 'ios/Podfile';
  final podfile = File(podfilePath);

  if (!podfile.existsSync()) {
    _printCheck('Podfile', false, 'Not found');
    return;
  }

  final content = podfile.readAsStringSync();
  final match =
      RegExp(r"platform\s*:ios\s*,\s*'(\d+\.\d+)'").firstMatch(content);

  if (match != null) {
    final version = double.tryParse(match.group(1) ?? '0') ?? 0;
    if (version >= 14.0) {
      _printCheck('iOS deployment target is ${match.group(1)} (>= 14.0)', true);
    } else {
      _printCheck(
          'iOS deployment target is ${match.group(1)}', false, 'Needs >= 14.0');
    }
  } else {
    _printCheck('iOS deployment target', true, 'Using project default');
  }
}

Future<void> _checkPackage() async {
  stdout.writeln(
      '║                                                               ║');
  stdout.writeln(
      '║  Checking package configuration...                            ║');

  // Check pubspec.yaml for locus dependency
  final pubspecFile = File('pubspec.yaml');
  if (pubspecFile.existsSync()) {
    final content = pubspecFile.readAsStringSync();
    if (content.contains('locus:') || content.contains('locus :')) {
      _printCheck('Locus dependency found', true);
    } else {
      _printCheck('Locus dependency', false, 'Not in pubspec.yaml');
    }
  }

  // Check Flutter version
  final flutterResult = await Process.run('flutter', ['--version']);
  if (flutterResult.exitCode == 0) {
    final output = flutterResult.stdout.toString();
    final versionMatch = RegExp(r'Flutter (\d+\.\d+\.\d+)').firstMatch(output);
    if (versionMatch != null) {
      _printCheck('Flutter version: ${versionMatch.group(1)}', true);
    }
  }
}

void _printCheck(String message, bool passed, [String? note]) {
  final icon = passed ? '✓' : '✗';
  final noteStr = note != null ? ' ($note)' : '';
  final fullMessage = '$message$noteStr';
  final padding = 57 - fullMessage.length;
  final paddedMessage = fullMessage + ' ' * (padding > 0 ? padding : 0);
  stdout.writeln('║  $icon $paddedMessage║');
}

void _printFix(String message) {
  final padding = 55 - message.length;
  final paddedMessage = message + ' ' * (padding > 0 ? padding : 0);
  stdout.writeln('║    → $paddedMessage║');
}
