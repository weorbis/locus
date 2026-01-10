import 'dart:io';

/// Represents a single package/app in a monorepo
class PackageInMonorepo {
  PackageInMonorepo({
    required this.path,
    required this.name,
    required this.isApp,
    this.usesLocus = false,
  });
  final String path;
  final String name;
  final bool isApp;
  final bool usesLocus;

  String get displayName => isApp ? '$name (app)' : name;

  PackageInMonorepo copyWith({bool? usesLocus}) => PackageInMonorepo(
        path: path,
        name: name,
        isApp: isApp,
        usesLocus: usesLocus ?? this.usesLocus,
      );

  @override
  String toString() =>
      'Package: $path (name: $name, isApp: $isApp, usesLocus: $usesLocus)';

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'isApp': isApp,
        'usesLocus': usesLocus,
      };
}

/// Result of monorepo detection
class MonorepoDetectionResult {
  MonorepoDetectionResult({
    required this.isMonorepo,
    required this.packages,
    required this.packagesWithLocus,
    required this.rootPath,
  });
  final bool isMonorepo;
  final List<PackageInMonorepo> packages;
  final List<PackageInMonorepo> packagesWithLocus;
  final String rootPath;

  bool get hasLocusUsage => packagesWithLocus.isNotEmpty;
  int get totalPackages => packages.length;
  int get locusPackageCount => packagesWithLocus.length;
}

/// Detects and manages monorepo structures
class MonorepoDetector {
  /// Common monorepo directory patterns (e.g., packages/, apps/, modules/)
  static const _monorepoSubdirs = {
    'packages',
    'apps',
    'modules',
    'plugins',
    'features',
    'libs',
    'projects',
    'examples',
    'samples',
  };

  /// Finds all Dart packages in a directory structure with Locus usage detection
  static Future<MonorepoDetectionResult> detectMonorepo(
    Directory rootDir,
  ) async {
    final packages = await findPackages(rootDir);
    final packagesWithLocus = <PackageInMonorepo>[];

    // Check each package for Locus usage
    for (var package in packages) {
      final usesLocus = await _checkLocusUsage(Directory(package.path));
      if (usesLocus) {
        packagesWithLocus.add(package.copyWith(usesLocus: true));
      }
    }

    return MonorepoDetectionResult(
      isMonorepo: packages.length > 1,
      packages: packages,
      packagesWithLocus: packagesWithLocus,
      rootPath: rootDir.absolute.path,
    );
  }

  /// Finds all Dart packages in a directory structure
  /// Returns a list of packages found, empty if not a monorepo
  static Future<List<PackageInMonorepo>> findPackages(
    Directory rootDir,
  ) async {
    final packages = <PackageInMonorepo>[];
    final visited = <String>{};

    // Check if root has pubspec.yaml - single project case
    final rootPubspec = File('${rootDir.path}/pubspec.yaml');
    if (rootPubspec.existsSync()) {
      final name = await _extractPackageName(rootPubspec);
      final rootPath = rootDir.absolute.path;
      if (!visited.contains(rootPath)) {
        visited.add(rootPath);
        packages.add(PackageInMonorepo(
          path: rootPath,
          name: name ?? 'root',
          isApp: await _isFlutterApp(rootDir),
        ));
      }
    }

    // Check common monorepo subdirectories first (packages/, apps/, etc.)
    for (final subdir in _monorepoSubdirs) {
      final subdirPath = Directory('${rootDir.path}/$subdir');
      if (subdirPath.existsSync()) {
        final subPackages = await _findPackagesInDirectory(subdirPath, visited);
        packages.addAll(subPackages);
      }
    }

    // Also check immediate subdirectories for packages
    final subPackages = await _findSubPackages(rootDir, visited);
    packages.addAll(subPackages);

    return packages;
  }

  /// Checks if this is a monorepo (multiple packages found)
  static Future<bool> isMonorepo(Directory rootDir) async {
    final packages = await findPackages(rootDir);
    return packages.length > 1;
  }

  /// Finds packages in a specific directory (e.g., packages/)
  static Future<List<PackageInMonorepo>> _findPackagesInDirectory(
    Directory dir,
    Set<String> visited,
  ) async {
    final packages = <PackageInMonorepo>[];

    try {
      await for (final entity in dir.list(recursive: false)) {
        if (entity is Directory && !_shouldIgnoreDir(entity.path)) {
          final pubspec = File('${entity.path}/pubspec.yaml');
          if (pubspec.existsSync()) {
            final path = entity.absolute.path;
            if (!visited.contains(path)) {
              visited.add(path);
              final name = await _extractPackageName(pubspec);
              packages.add(PackageInMonorepo(
                path: path,
                name: name ?? entity.path.split('/').last,
                isApp: await _isFlutterApp(entity),
              ));
            }
          }
        }
      }
    } catch (e) {
      // Silently handle permission errors or other IO issues
    }

    return packages;
  }

  /// Finds all pubspec.yaml files in immediate subdirectories
  static Future<List<PackageInMonorepo>> _findSubPackages(
    Directory dir,
    Set<String> visited,
  ) async {
    final packages = <PackageInMonorepo>[];

    try {
      await for (final entity in dir.list(recursive: false)) {
        if (entity is Directory && !_shouldIgnoreDir(entity.path)) {
          // Skip monorepo subdirs as they're handled separately
          final dirName = entity.path.split('/').last;
          if (_monorepoSubdirs.contains(dirName)) continue;

          final pubspec = File('${entity.path}/pubspec.yaml');
          if (pubspec.existsSync()) {
            final path = entity.absolute.path;
            if (!visited.contains(path)) {
              visited.add(path);
              final name = await _extractPackageName(pubspec);
              packages.add(PackageInMonorepo(
                path: path,
                name: name ?? dirName,
                isApp: await _isFlutterApp(entity),
              ));
            }
          }
        }
      }
    } catch (e) {
      // Silently handle permission errors or other IO issues
    }

    return packages;
  }

  /// Checks if a package uses Locus SDK
  static Future<bool> _checkLocusUsage(Directory packageDir) async {
    final pubspec = File('${packageDir.path}/pubspec.yaml');
    if (!pubspec.existsSync()) return false;

    try {
      final content = await pubspec.readAsString();
      // Check for locus dependency
      if (content.contains('locus:') || content.contains('locus :')) {
        return true;
      }

      // Also check lib/ directory for locus imports
      final libDir = Directory('${packageDir.path}/lib');
      if (libDir.existsSync()) {
        await for (final file in libDir.list(recursive: true)) {
          if (file is File && file.path.endsWith('.dart')) {
            final fileContent = await file.readAsString();
            if (fileContent.contains("import 'package:locus") ||
                fileContent.contains('import "package:locus')) {
              return true;
            }
          }
        }
      }
    } catch (_) {
      // Ignore errors
    }

    return false;
  }

  /// Extracts package name from pubspec.yaml
  static Future<String?> _extractPackageName(File pubspec) async {
    try {
      final content = await pubspec.readAsString();
      for (final line in content.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('name:')) {
          return trimmed
              .substring(5)
              .trim()
              .replaceAll('"', '')
              .replaceAll("'", '');
        }
      }
    } catch (_) {
      // Ignore errors
    }
    return null;
  }

  /// Checks if a directory is a Flutter app
  static Future<bool> _isFlutterApp(Directory dir) async {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (!pubspec.existsSync()) return false;

    try {
      final content = await pubspec.readAsString();
      // Check for flutter SDK dependency
      if (content.contains('sdk: flutter')) {
        // Check if it has a main.dart (indicates app vs package)
        final mainDart = File('${dir.path}/lib/main.dart');
        if (mainDart.existsSync()) return true;

        // Also check for flutter: uses-material-design or similar app indicators
        if (content.contains('uses-material-design:') ||
            content.contains('assets:') ||
            content.contains('fonts:')) {
          return true;
        }
      }
    } catch (_) {
      // Ignore errors
    }

    return false;
  }

  /// Directories to ignore when searching for packages
  static bool _shouldIgnoreDir(String path) {
    final dirName = path.split('/').last;

    // Hidden directories
    if (dirName.startsWith('.')) return true;

    final ignoredDirs = {
      'build',
      'dist',
      'coverage',
      'doc',
      'docs',
      '.dart_tool',
      '.git',
      'node_modules',
      '.pub-cache',
      '.pub',
      '.github',
      '.vscode',
      '.idea',
      '.gradle',
      'gradle',
      'ios',
      'android',
      'web',
      'windows',
      'macos',
      'linux',
      '__pycache__',
      'test_driver',
    };

    return ignoredDirs.contains(dirName);
  }
}
