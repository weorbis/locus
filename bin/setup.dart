/// Locus CLI - Setup Wizard
///
/// Automatically configures Android and iOS platform files for Locus.
///
/// Usage:
///   `dart run locus:setup [options]`
///
/// Options:
///   -i, --interactive    Run in interactive mode with prompts
///   --android-only       Only configure Android
///   --ios-only           Only configure iOS
///   --activity           Include activity recognition permissions
///   --no-activity        Skip activity recognition permissions
///   -h, --help           Show this help message
library;

import 'dart:io';

import 'package:args/args.dart';

const _version = '2.0.0';

const _header = '''
╔══════════════════════════════════════════════════════════════╗
║                    Locus - Setup Wizard                       ║
╠══════════════════════════════════════════════════════════════╣
''';

const _footer = '''
║                                                               ║
║  ────────────────────────────────────────────────────────────║
║  ✅ Setup complete! Run `dart run locus:doctor` to verify.    ║
║                                                               ║
╚══════════════════════════════════════════════════════════════╝
''';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('interactive',
        abbr: 'i', defaultsTo: false, help: 'Interactive mode')
    ..addFlag('android-only', defaultsTo: false, help: 'Only configure Android')
    ..addFlag('ios-only', defaultsTo: false, help: 'Only configure iOS')
    ..addFlag('activity',
        defaultsTo: true, help: 'Include activity recognition')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help');

  ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    stdout.writeln('Error: $e');
    stdout.writeln('Usage: dart run locus:setup [options]');
    stdout.writeln(parser.usage);
    exit(1);
  }

  if (results['help'] as bool) {
    stdout.writeln('Locus Setup Wizard v$_version');
    stdout.writeln('');
    stdout.writeln(
        'Automatically configures Android and iOS platform files for Locus.');
    stdout.writeln('');
    stdout.writeln('Usage: dart run locus:setup [options]');
    stdout.writeln('');
    stdout.writeln(parser.usage);
    exit(0);
  }

  final androidOnly = results['android-only'] as bool;
  final iosOnly = results['ios-only'] as bool;
  final includeActivity = results['activity'] as bool;
  final interactive = results['interactive'] as bool;

  stdout.writeln(_header);

  var hasErrors = false;

  if (!iosOnly) {
    final androidResult = await setupAndroid(includeActivity: includeActivity);
    if (!androidResult) hasErrors = true;
  }

  if (!androidOnly) {
    final iosResult = await setupIos(
      interactive: interactive,
      includeActivity: includeActivity,
    );
    if (!iosResult) hasErrors = true;
  }

  if (hasErrors) {
    stdout.writeln('''
║                                                               ║
║  ────────────────────────────────────────────────────────────║
║  ⚠️  Setup completed with warnings. Review messages above.    ║
║                                                               ║
╚══════════════════════════════════════════════════════════════╝
''');
  } else {
    stdout.writeln(_footer);
  }
}

Future<bool> setupAndroid({required bool includeActivity}) async {
  stdout.writeln(
      '║                                                               ║');
  stdout.writeln(
      '║  Setting up Android...                                        ║');

  const manifestPath = 'android/app/src/main/AndroidManifest.xml';
  final manifestFile = File(manifestPath);

  if (!manifestFile.existsSync()) {
    stdout.writeln(
        '║  ✗ AndroidManifest.xml not found at $manifestPath           ║');
    stdout.writeln(
        '║    Run this command from your Flutter project root.         ║');
    return false;
  }

  var content = manifestFile.readAsStringSync();

  // Required permissions for background location
  final permissions = <String>[
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.ACCESS_BACKGROUND_LOCATION',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_LOCATION',
    'android.permission.WAKE_LOCK',
    'android.permission.RECEIVE_BOOT_COMPLETED',
  ];

  if (includeActivity) {
    permissions.addAll([
      'android.permission.ACTIVITY_RECOGNITION',
      'com.google.android.gms.permission.ACTIVITY_RECOGNITION',
    ]);
  }

  var modified = false;

  for (final permission in permissions) {
    final permName = permission.split('.').last;
    if (!content.contains(permission)) {
      // Add permission before </manifest>
      final insertPoint = content.lastIndexOf('</manifest>');
      if (insertPoint != -1) {
        final permissionTag =
            '    <uses-permission android:name="$permission" />\n';
        content = content.substring(0, insertPoint) +
            permissionTag +
            content.substring(insertPoint);
        modified = true;
        _printStatus('Added $permName permission');
      }
    } else {
      _printStatus('$permName permission (already present)', isNew: false);
    }
  }

  if (modified) {
    manifestFile.writeAsStringSync(content);
  }

  // Check build.gradle for minSdkVersion
  await _checkAndroidMinSdk();

  return true;
}

Future<void> _checkAndroidMinSdk() async {
  const gradlePath = 'android/app/build.gradle';
  const gradleKtsPath = 'android/app/build.gradle.kts';

  File? gradleFile;

  if (File(gradleKtsPath).existsSync()) {
    gradleFile = File(gradleKtsPath);
  } else if (File(gradlePath).existsSync()) {
    gradleFile = File(gradlePath);
  }

  if (gradleFile == null) {
    _printStatus('build.gradle not found - verify minSdkVersion >= 26',
        isWarning: true);
    return;
  }

  final content = gradleFile.readAsStringSync();

  // Try to find minSdkVersion
  final patterns = [
    RegExp(r'minSdkVersion\s*[=:]\s*(\d+)'),
    RegExp(r'minSdk\s*[=:]\s*(\d+)'),
    RegExp(r'minSdkVersion\.get\(\)'), // Flutter's default
  ];

  int? minSdk;
  for (final pattern in patterns) {
    final match = pattern.firstMatch(content);
    if (match != null && match.groupCount >= 1) {
      minSdk = int.tryParse(match.group(1) ?? '');
      break;
    }
  }

  if (minSdk != null) {
    if (minSdk >= 26) {
      _printStatus('minSdkVersion is $minSdk (required: >= 26)', isNew: false);
    } else {
      _printStatus('minSdkVersion is $minSdk - needs to be >= 26',
          isWarning: true);
    }
  } else {
    // Flutter's default uses flutter.minSdkVersion which is usually fine
    if (content.contains('flutter.minSdkVersion') ||
        content.contains('minSdkVersion.get()')) {
      _printStatus('Using Flutter default minSdkVersion', isNew: false);
    } else {
      _printStatus('Could not detect minSdkVersion - verify >= 26',
          isWarning: true);
    }
  }
}

Future<bool> setupIos({
  required bool interactive,
  required bool includeActivity,
}) async {
  stdout.writeln(
      '║                                                               ║');
  stdout.writeln(
      '║  Setting up iOS...                                            ║');

  const plistPath = 'ios/Runner/Info.plist';
  final plistFile = File(plistPath);

  if (!plistFile.existsSync()) {
    stdout.writeln(
        '║  ✗ Info.plist not found at $plistPath                       ║');
    stdout.writeln(
        '║    Run this command from your Flutter project root.         ║');
    return false;
  }

  var content = plistFile.readAsStringSync();

  // Required Info.plist keys
  final keysToAdd = <String, String>{
    'NSLocationWhenInUseUsageDescription':
        'This app needs location access to track your position.',
    'NSLocationAlwaysAndWhenInUseUsageDescription':
        'This app needs background location access to track your route.',
  };

  if (includeActivity) {
    keysToAdd['NSMotionUsageDescription'] =
        'This app uses motion data to detect your activity.';
  }

  var modified = false;

  for (final entry in keysToAdd.entries) {
    if (!content.contains('<key>${entry.key}</key>')) {
      content = _addPlistKey(content, entry.key, entry.value);
      modified = true;
      _printStatus('Added ${entry.key}');
    } else {
      _printStatus('${entry.key} (already present)', isNew: false);
    }
  }

  // Add UIBackgroundModes with location
  if (!content.contains('<string>location</string>')) {
    content = _addBackgroundMode(content, 'location');
    modified = true;
    _printStatus('Added location to UIBackgroundModes');
  } else {
    _printStatus('UIBackgroundModes includes location (already present)',
        isNew: false);
  }

  // Add BGTaskSchedulerPermittedIdentifiers
  if (!content.contains('dev.locus')) {
    content = _addBgTaskIdentifier(content, 'dev.locus.refresh');
    modified = true;
    _printStatus('Added BGTaskScheduler identifier');
  } else {
    _printStatus('BGTaskScheduler identifier (already present)', isNew: false);
  }

  if (modified) {
    plistFile.writeAsStringSync(content);
  }

  // Check iOS deployment target
  await _checkIosDeploymentTarget();

  return true;
}

Future<void> _checkIosDeploymentTarget() async {
  const podfilePath = 'ios/Podfile';
  final podfile = File(podfilePath);

  if (!podfile.existsSync()) {
    return;
  }

  final content = podfile.readAsStringSync();
  final match =
      RegExp(r"platform\s*:ios\s*,\s*'(\d+\.\d+)'").firstMatch(content);

  if (match != null) {
    final version = double.tryParse(match.group(1) ?? '0') ?? 0;
    if (version >= 14.0) {
      _printStatus(
          'iOS deployment target is ${match.group(1)} (required: >= 14.0)',
          isNew: false);
    } else {
      _printStatus(
          'iOS deployment target is ${match.group(1)} - needs to be >= 14.0',
          isWarning: true);
    }
  }
}

String _addPlistKey(String content, String key, String value) {
  // Find the position just before </dict> at the end
  final insertPoint = content.lastIndexOf('</dict>');
  if (insertPoint == -1) return content;

  final keyValue = '''
\t<key>$key</key>
\t<string>$value</string>
''';

  return content.substring(0, insertPoint) +
      keyValue +
      content.substring(insertPoint);
}

String _addBackgroundMode(String content, String mode) {
  // Check if UIBackgroundModes already exists
  if (content.contains('<key>UIBackgroundModes</key>')) {
    // Add to existing array
    final arrayStart =
        content.indexOf('<array>', content.indexOf('UIBackgroundModes'));
    if (arrayStart != -1) {
      final insertPoint = arrayStart + '<array>'.length;
      final modeEntry = '\n\t\t<string>$mode</string>';
      return content.substring(0, insertPoint) +
          modeEntry +
          content.substring(insertPoint);
    }
  } else {
    // Create new UIBackgroundModes entry
    final insertPoint = content.lastIndexOf('</dict>');
    if (insertPoint != -1) {
      final bgModes = '''
\t<key>UIBackgroundModes</key>
\t<array>
\t\t<string>$mode</string>
\t</array>
''';
      return content.substring(0, insertPoint) +
          bgModes +
          content.substring(insertPoint);
    }
  }
  return content;
}

String _addBgTaskIdentifier(String content, String identifier) {
  // Check if BGTaskSchedulerPermittedIdentifiers exists
  if (content.contains('<key>BGTaskSchedulerPermittedIdentifiers</key>')) {
    // Add to existing array
    final arrayStart = content.indexOf(
        '<array>', content.indexOf('BGTaskSchedulerPermittedIdentifiers'));
    if (arrayStart != -1) {
      final insertPoint = arrayStart + '<array>'.length;
      final idEntry = '\n\t\t<string>$identifier</string>';
      return content.substring(0, insertPoint) +
          idEntry +
          content.substring(insertPoint);
    }
  } else {
    // Create new entry
    final insertPoint = content.lastIndexOf('</dict>');
    if (insertPoint != -1) {
      final bgTask = '''
\t<key>BGTaskSchedulerPermittedIdentifiers</key>
\t<array>
\t\t<string>$identifier</string>
\t</array>
''';
      return content.substring(0, insertPoint) +
          bgTask +
          content.substring(insertPoint);
    }
  }
  return content;
}

void _printStatus(String message, {bool isNew = true, bool isWarning = false}) {
  final icon = isWarning ? '⚠' : (isNew ? '✓' : '✓');
  final padding = 60 - message.length - 4;
  final paddedMessage = message + ' ' * (padding > 0 ? padding : 0);
  stdout.writeln('║  $icon $paddedMessage║');
}
