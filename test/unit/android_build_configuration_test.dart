import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android buildscript does not pin host plugin versions', () {
    final buildScript = File('android/build.gradle.kts').readAsStringSync();

    expect(
      buildScript,
      isNot(contains('com.android.tools.build:gradle:')),
      reason:
          'A plugin-local AGP copy creates incompatible Gradle classloaders.',
    );
    expect(
      buildScript,
      isNot(contains('org.jetbrains.kotlin:kotlin-gradle-plugin:')),
      reason:
          'A plugin-local Kotlin Gradle Plugin copy can diverge from the host.',
    );
  });
}
