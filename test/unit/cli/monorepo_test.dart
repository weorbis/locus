import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Import the monorepo module - adjust path based on your test setup
import '../../../bin/src/migrate/monorepo.dart';

void main() {
  group('PackageInMonorepo', () {
    test('displayName shows (app) suffix for apps', () {
      final package = PackageInMonorepo(
        path: '/test/app',
        name: 'my_app',
        isApp: true,
      );
      expect(package.displayName, equals('my_app (app)'));
    });

    test('displayName shows just name for packages', () {
      final package = PackageInMonorepo(
        path: '/test/pkg',
        name: 'my_package',
        isApp: false,
      );
      expect(package.displayName, equals('my_package'));
    });

    test('copyWith preserves values and updates usesLocus', () {
      final package = PackageInMonorepo(
        path: '/test/pkg',
        name: 'my_package',
        isApp: false,
        usesLocus: false,
      );
      final updated = package.copyWith(usesLocus: true);
      expect(updated.path, equals('/test/pkg'));
      expect(updated.name, equals('my_package'));
      expect(updated.isApp, isFalse);
      expect(updated.usesLocus, isTrue);
    });

    test('toJson returns correct map', () {
      final package = PackageInMonorepo(
        path: '/test/pkg',
        name: 'my_package',
        isApp: true,
        usesLocus: true,
      );
      final json = package.toJson();
      expect(json['path'], equals('/test/pkg'));
      expect(json['name'], equals('my_package'));
      expect(json['isApp'], isTrue);
      expect(json['usesLocus'], isTrue);
    });
  });

  group('MonorepoDetectionResult', () {
    test('hasLocusUsage returns true when packages use Locus', () {
      final result = MonorepoDetectionResult(
        isMonorepo: true,
        packages: [
          PackageInMonorepo(path: '/a', name: 'a', isApp: false),
          PackageInMonorepo(path: '/b', name: 'b', isApp: true),
        ],
        packagesWithLocus: [
          PackageInMonorepo(
              path: '/a', name: 'a', isApp: false, usesLocus: true),
        ],
        rootPath: '/root',
      );
      expect(result.hasLocusUsage, isTrue);
      expect(result.locusPackageCount, equals(1));
    });

    test('hasLocusUsage returns false when no packages use Locus', () {
      final result = MonorepoDetectionResult(
        isMonorepo: true,
        packages: [
          PackageInMonorepo(path: '/a', name: 'a', isApp: false),
        ],
        packagesWithLocus: [],
        rootPath: '/root',
      );
      expect(result.hasLocusUsage, isFalse);
      expect(result.locusPackageCount, equals(0));
    });
  });

  group('MonorepoDetector', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('monorepo_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('findPackages returns empty list for empty directory', () async {
      final packages = await MonorepoDetector.findPackages(tempDir);
      expect(packages, isEmpty);
    });

    test('findPackages detects single package at root', () async {
      // Create pubspec.yaml at root
      await File('${tempDir.path}/pubspec.yaml').writeAsString('''
name: single_package
version: 1.0.0
''');

      final packages = await MonorepoDetector.findPackages(tempDir);
      expect(packages, hasLength(1));
      expect(packages.first.name, equals('single_package'));
    });

    test('findPackages detects packages in packages/ subdirectory', () async {
      // Create packages directory with two packages
      await Directory('${tempDir.path}/packages/pkg_a').create(recursive: true);
      await Directory('${tempDir.path}/packages/pkg_b').create(recursive: true);

      await File('${tempDir.path}/packages/pkg_a/pubspec.yaml')
          .writeAsString('''
name: pkg_a
version: 1.0.0
''');

      await File('${tempDir.path}/packages/pkg_b/pubspec.yaml')
          .writeAsString('''
name: pkg_b
version: 1.0.0
''');

      final packages = await MonorepoDetector.findPackages(tempDir);
      expect(packages, hasLength(2));
      expect(packages.map((p) => p.name), containsAll(['pkg_a', 'pkg_b']));
    });

    test('findPackages detects root + subdirectory packages (monorepo)',
        () async {
      // Create root package
      await File('${tempDir.path}/pubspec.yaml').writeAsString('''
name: root_pkg
version: 1.0.0
''');

      // Create packages directory
      await Directory('${tempDir.path}/packages/sub_pkg')
          .create(recursive: true);
      await File('${tempDir.path}/packages/sub_pkg/pubspec.yaml')
          .writeAsString('''
name: sub_pkg
version: 1.0.0
''');

      final packages = await MonorepoDetector.findPackages(tempDir);
      expect(packages, hasLength(2));
      expect(packages.map((p) => p.name), containsAll(['root_pkg', 'sub_pkg']));
    });

    test('isMonorepo returns true for multiple packages', () async {
      await Directory('${tempDir.path}/packages/pkg_a').create(recursive: true);
      await Directory('${tempDir.path}/packages/pkg_b').create(recursive: true);

      await File('${tempDir.path}/packages/pkg_a/pubspec.yaml')
          .writeAsString('name: pkg_a');
      await File('${tempDir.path}/packages/pkg_b/pubspec.yaml')
          .writeAsString('name: pkg_b');

      expect(await MonorepoDetector.isMonorepo(tempDir), isTrue);
    });

    test('isMonorepo returns false for single package', () async {
      await File('${tempDir.path}/pubspec.yaml').writeAsString('name: single');

      expect(await MonorepoDetector.isMonorepo(tempDir), isFalse);
    });

    test('findPackages ignores build directories', () async {
      // Create a package in build directory (should be ignored)
      await Directory('${tempDir.path}/build/pkg').create(recursive: true);
      await File('${tempDir.path}/build/pkg/pubspec.yaml')
          .writeAsString('name: build_pkg');

      // Create a real package
      await File('${tempDir.path}/pubspec.yaml')
          .writeAsString('name: real_pkg');

      final packages = await MonorepoDetector.findPackages(tempDir);
      expect(packages, hasLength(1));
      expect(packages.first.name, equals('real_pkg'));
    });

    test('findPackages ignores hidden directories', () async {
      // Create a package in hidden directory (should be ignored)
      await Directory('${tempDir.path}/.hidden/pkg').create(recursive: true);
      await File('${tempDir.path}/.hidden/pkg/pubspec.yaml')
          .writeAsString('name: hidden_pkg');

      // Create a real package
      await File('${tempDir.path}/pubspec.yaml')
          .writeAsString('name: real_pkg');

      final packages = await MonorepoDetector.findPackages(tempDir);
      expect(packages, hasLength(1));
      expect(packages.first.name, equals('real_pkg'));
    });

    test('detectMonorepo identifies packages with Locus usage', () async {
      // Create package with Locus dependency
      await Directory('${tempDir.path}/packages/with_locus')
          .create(recursive: true);
      await File('${tempDir.path}/packages/with_locus/pubspec.yaml')
          .writeAsString('''
name: with_locus
dependencies:
  locus: ^2.0.0
''');

      // Create package without Locus
      await Directory('${tempDir.path}/packages/no_locus')
          .create(recursive: true);
      await File('${tempDir.path}/packages/no_locus/pubspec.yaml')
          .writeAsString('''
name: no_locus
dependencies:
  flutter: sdk
''');

      final result = await MonorepoDetector.detectMonorepo(tempDir);
      expect(result.isMonorepo, isTrue);
      expect(result.totalPackages, equals(2));
      expect(result.locusPackageCount, equals(1));
      expect(result.packagesWithLocus.first.name, equals('with_locus'));
    });

    test('detectMonorepo detects Locus imports in lib/', () async {
      // Create package with Locus import
      await Directory('${tempDir.path}/lib').create(recursive: true);
      await File('${tempDir.path}/pubspec.yaml').writeAsString('name: app');
      await File('${tempDir.path}/lib/main.dart').writeAsString('''
import 'package:locus/locus.dart';

void main() {
  Locus.ready();
}
''');

      final result = await MonorepoDetector.detectMonorepo(tempDir);
      expect(result.hasLocusUsage, isTrue);
    });

    test('findPackages detects Flutter apps correctly', () async {
      // Create Flutter app
      await Directory('${tempDir.path}/lib').create(recursive: true);
      await File('${tempDir.path}/pubspec.yaml').writeAsString('''
name: my_flutter_app
dependencies:
  flutter:
    sdk: flutter
''');
      await File('${tempDir.path}/lib/main.dart')
          .writeAsString('void main() {}');

      final packages = await MonorepoDetector.findPackages(tempDir);
      expect(packages, hasLength(1));
      expect(packages.first.isApp, isTrue);
    });

    test('findPackages handles common monorepo patterns', () async {
      // Create apps/ and packages/ structure (common pattern)
      await Directory('${tempDir.path}/apps/app1/lib').create(recursive: true);
      await Directory('${tempDir.path}/packages/shared')
          .create(recursive: true);

      await File('${tempDir.path}/apps/app1/pubspec.yaml').writeAsString('''
name: app1
dependencies:
  flutter:
    sdk: flutter
''');
      await File('${tempDir.path}/apps/app1/lib/main.dart')
          .writeAsString('void main() {}');

      await File('${tempDir.path}/packages/shared/pubspec.yaml')
          .writeAsString('''
name: shared
''');

      final packages = await MonorepoDetector.findPackages(tempDir);
      expect(packages, hasLength(2));

      final app = packages.firstWhere((p) => p.name == 'app1');
      final pkg = packages.firstWhere((p) => p.name == 'shared');

      expect(app.isApp, isTrue);
      expect(pkg.isApp, isFalse);
    });
  });
}
