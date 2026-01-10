import 'dart:io';
import 'patterns.dart';
import 'monorepo.dart';

class MigrationAnalysisResult {
  MigrationAnalysisResult({
    required this.projectPath,
    required this.timestamp,
    required this.analyzedFiles,
    required this.matches,
    required this.warnings,
    required this.errors,
    required this.importedPackages,
  });
  final String projectPath;
  final DateTime timestamp;
  final List<AnalyzedFile> analyzedFiles;
  final List<PatternMatch> matches;
  final List<MigrationWarning> warnings;
  final List<MigrationError> errors;
  final Set<String> importedPackages;

  int get totalFiles => analyzedFiles.length;
  int get filesWithLocus => analyzedFiles.where((f) => f.hasLocusUsage).length;
  int get totalMatches => matches.length;

  Map<String, int> get matchesByCategory {
    final counts = <String, int>{};
    for (final match in matches) {
      final pattern = MigrationPatternDatabase.allPatterns.firstWhere(
          (p) => p.id == match.patternId,
          orElse: () =>
              throw Exception('Pattern not found: ${match.patternId}'));
      counts[pattern.category.name] = (counts[pattern.category.name] ?? 0) + 1;
    }
    return counts;
  }

  int get autoMigratableCount {
    return matches.where((m) {
      final pattern = MigrationPatternDatabase.allPatterns
          .firstWhere((p) => p.id == m.patternId);
      return pattern.confidence == MigrationConfidence.high;
    }).length;
  }

  int get manualReviewCount {
    return matches.where((m) {
      final pattern = MigrationPatternDatabase.allPatterns
          .firstWhere((p) => p.id == m.patternId);
      return pattern.confidence == MigrationConfidence.low;
    }).length;
  }

  int get removedFeaturesCount {
    return matches.where((m) {
      final pattern = MigrationPatternDatabase.allPatterns
          .firstWhere((p) => p.id == m.patternId);
      return pattern.category == MigrationCategory.removed;
    }).length;
  }

  Map<String, dynamic> toJson() => {
        'projectPath': projectPath,
        'timestamp': timestamp.toIso8601String(),
        'summary': {
          'totalFiles': totalFiles,
          'filesWithLocus': filesWithLocus,
          'totalMatches': totalMatches,
          'autoMigratable': autoMigratableCount,
          'manualReview': manualReviewCount,
          'removedFeatures': removedFeaturesCount,
          'matchesByCategory': matchesByCategory,
        },
        'files': analyzedFiles.map((f) => f.toJson()).toList(),
        'matches': matches.map((m) => m.toJson()).toList(),
        'warnings': warnings.map((w) => w.toJson()).toList(),
        'errors': errors.map((e) => e.toJson()).toList(),
        'importedPackages': importedPackages.toList(),
      };
}

class AnalyzedFile {
  AnalyzedFile({
    required this.path,
    required this.content,
    required this.lineCount,
    required this.hasLocusUsage,
    required this.locusMethods,
    required this.imports,
    required this.locusMatchCount,
  });
  final String path;
  final String content;
  final int lineCount;
  final bool hasLocusUsage;
  final Set<String> locusMethods;
  final Set<String> imports;
  final int locusMatchCount;

  Map<String, dynamic> toJson() => {
        'path': path,
        'lineCount': lineCount,
        'hasLocusUsage': hasLocusUsage,
        'locusMethods': locusMethods.toList(),
        'imports': imports.toList(),
        'locusMatchCount': locusMatchCount,
      };
}

class MigrationWarning {
  MigrationWarning({
    required this.filePath,
    required this.line,
    required this.message,
    required this.code,
    this.suggestion,
  });
  final String filePath;
  final int line;
  final String message;
  final String code;
  final String? suggestion;

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'line': line,
        'message': message,
        'code': code,
        'suggestion': suggestion,
      };
}

class MigrationError {
  MigrationError({
    required this.filePath,
    required this.line,
    required this.message,
    required this.code,
  });
  final String filePath;
  final int line;
  final String message;
  final String code;

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'line': line,
        'message': message,
        'code': code,
      };
}

class MigrationAnalyzer {
  MigrationAnalyzer({
    List<MigrationPattern>? patterns,
    Set<String>? ignoredPatterns,
    Set<String>? onlyCategories,
    bool verbose = false,
  })  : _patterns = _filterPatternsByCategory(
          patterns ?? MigrationPatternDatabase.allPatterns,
          onlyCategories,
        ),
        _ignoredPatterns = ignoredPatterns ?? {},
        _onlyCategories = _parseCategories(onlyCategories),
        _verbose = verbose;
  final List<MigrationPattern> _patterns;
  final Set<String> _ignoredPatterns;
  final Set<MigrationCategory> _onlyCategories;
  final bool _verbose;

  static List<MigrationPattern> _filterPatternsByCategory(
    List<MigrationPattern> patterns,
    Set<String>? onlyCategories,
  ) {
    if (onlyCategories == null || onlyCategories.isEmpty) {
      return patterns;
    }
    final categories = _parseCategories(onlyCategories);
    return patterns.where((p) => categories.contains(p.category)).toList();
  }

  static Set<MigrationCategory> _parseCategories(Set<String>? categoryNames) {
    if (categoryNames == null || categoryNames.isEmpty) {
      return MigrationCategory.values.toSet();
    }
    return categoryNames
        .map((name) => MigrationCategory.values.firstWhere(
              (c) => c.name.toLowerCase() == name.toLowerCase(),
              orElse: () => throw ArgumentError('Unknown category: $name'),
            ))
        .toSet();
  }

  /// Returns the set of categories being analyzed.
  Set<MigrationCategory> get activeCategories => _onlyCategories;

  Future<MigrationAnalysisResult> analyze(
    Directory projectDir, {
    bool skipTests = false,
    Set<String>? additionalIgnores,
  }) async {
    final stopwatch = Stopwatch()..start();

    if (_verbose) {
      stdout.writeln('[INFO] Starting analysis of ${projectDir.path}');
    }

    final analyzedFiles = <AnalyzedFile>[];
    final allMatches = <PatternMatch>[];
    final warnings = <MigrationWarning>[];
    final errors = <MigrationError>[];
    final importedPackages = <String>{};

    final ignorePatterns = {..._ignoredPatterns, ...?additionalIgnores};
    final gitignorePatterns = await _parseGitignore(projectDir);

    final files = await _findDartFiles(
      projectDir,
      skipTests: skipTests,
      ignorePatterns: {...ignorePatterns, ...gitignorePatterns},
    );

    if (_verbose) {
      stdout.writeln('[INFO] Found ${files.length} Dart files to analyze');
    }

    for (final file in files) {
      try {
        final content = await file.readAsString();
        final fileResult = await _analyzeFile(
          file,
          content,
          projectDir.path,
        );

        analyzedFiles.add(fileResult);

        if (fileResult.hasLocusUsage) {
          allMatches.addAll(
            _findMatchesInContent(content, file.path, fileResult.imports),
          );
        }

        for (final import in fileResult.imports) {
          if (import.contains('locus')) {
            importedPackages.add(import);
          }
        }

        if (_verbose) {
          stdout.writeln(
              '[INFO] Analyzed ${file.path} - ${fileResult.locusMatchCount} Locus matches');
        }
      } catch (e, stack) {
        errors.add(MigrationError(
          filePath: file.path,
          line: 1,
          message: 'Failed to analyze file: $e',
          code: 'ANALYSIS_ERROR',
        ));

        if (_verbose) {
          stdout.writeln('[ERROR] Failed to analyze ${file.path}: $e');
          stdout.writeln(stack);
        }
      }
    }

    for (final match in allMatches) {
      final pattern = _patterns.firstWhere(
        (p) => p.id == match.patternId,
        orElse: () => throw Exception('Pattern not found: ${match.patternId}'),
      );

      if (pattern.category == MigrationCategory.removed) {
        warnings.add(MigrationWarning(
          filePath: match.filePath,
          line: match.line,
          message: 'Feature "${pattern.name}" is removed in v2.0',
          code: 'REMOVED_FEATURE',
          suggestion: 'Remove this line and implement the feature yourself',
        ));
      }

      if (pattern.confidence == MigrationConfidence.low) {
        warnings.add(MigrationWarning(
          filePath: match.filePath,
          line: match.line,
          message: 'Manual review required for "${pattern.name}"',
          code: 'MANUAL_REVIEW',
          suggestion: pattern.description,
        ));
      }
    }

    stopwatch.stop();

    if (_verbose) {
      stdout.writeln(
          '[INFO] Analysis completed in ${stopwatch.elapsedMilliseconds}ms');
      stdout.writeln(
          '[INFO] Found $allMatches matches across ${analyzedFiles.where((f) => f.hasLocusUsage).length} files');
    }

    return MigrationAnalysisResult(
      projectPath: projectDir.absolute.path,
      timestamp: DateTime.now(),
      analyzedFiles: analyzedFiles,
      matches: allMatches,
      warnings: warnings,
      errors: errors,
      importedPackages: importedPackages,
    );
  }

  Future<List<File>> _findDartFiles(
    Directory dir, {
    required bool skipTests,
    required Set<String> ignorePatterns,
  }) async {
    final files = <File>[];

    final ignoreSet = <String>{...ignorePatterns};
    ignoreSet.add('.dart_tool');
    ignoreSet.add('build');
    ignoreSet.add('.pub-cache');
    ignoreSet.add('node_modules');

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        if (skipTests && entity.path.contains('/test/')) continue;
        if (skipTests && entity.path.contains('/.dart_tool/')) continue;

        final relativePath = entity.path.replaceFirst('${dir.path}/', '');

        bool shouldIgnore = false;
        for (final pattern in ignoreSet) {
          if (relativePath.startsWith(pattern) ||
              relativePath.contains('/$pattern/') ||
              relativePath.endsWith('/$pattern')) {
            shouldIgnore = true;
            break;
          }
        }

        if (!shouldIgnore) {
          files.add(entity);
        }
      }
    }

    return files;
  }

  Future<Set<String>> _parseGitignore(Directory dir) async {
    final gitignoreFile = File('${dir.path}/.gitignore');
    if (!gitignoreFile.existsSync()) {
      return {};
    }

    final content = await gitignoreFile.readAsString();
    final patterns = <String>{};

    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
        patterns.add(trimmed);
      }
    }

    return patterns;
  }

  Future<AnalyzedFile> _analyzeFile(
    File file,
    String content,
    String projectPath,
  ) async {
    final lines = content.split('\n');
    final imports = <String>{};
    final locusMethods = <String>{};

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('import ')) {
        imports.add(_extractImport(trimmed));
      }
      if (trimmed.contains('Locus.')) {
        final match = RegExp(r'Locus\.(\w+)').firstMatch(trimmed);
        if (match != null) {
          locusMethods.add(match.group(1)!);
        }
      }
    }

    return AnalyzedFile(
      path: file.path,
      content: content,
      lineCount: lines.length,
      hasLocusUsage: locusMethods.isNotEmpty,
      locusMethods: locusMethods,
      imports: imports,
      locusMatchCount: locusMethods.length,
    );
  }

  String _extractImport(String line) {
    final match = RegExp(r"import\s+'([^']+)'").firstMatch(line);
    if (match != null) {
      return match.group(1)!;
    }
    final match2 = RegExp(r'import\s+"([^"]+)"').firstMatch(line);
    if (match2 != null) {
      return match2.group(1)!;
    }
    return line;
  }

  List<PatternMatch> _findMatchesInContent(
    String content,
    String filePath,
    Set<String> imports,
  ) {
    final matches = <PatternMatch>[];
    final lines = content.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      for (final pattern in _patterns) {
        final lineMatches = pattern.findMatches(line, filePath);

        for (final match in lineMatches) {
          matches.add(PatternMatch(
            filePath: filePath,
            line: i + 1,
            column: match.column,
            original: match.original,
            replacement: match.replacement,
            patternId: match.patternId,
          ));
        }
      }
    }

    return matches;
  }

  List<MigrationPattern> get patterns => _patterns;

  /// Analyzes multiple packages in a monorepo and aggregates results
  Future<MonorepoMigrationAnalysisResult> analyzeMonorepo(
    Directory rootDir, {
    bool skipTests = false,
    Set<String>? additionalIgnores,
  }) async {
    final stopwatch = Stopwatch()..start();

    if (_verbose) {
      stdout.writeln('[INFO] Detecting monorepo structure...');
    }

    final packages = await MonorepoDetector.findPackages(rootDir);

    if (_verbose) {
      stdout.writeln(
          '[INFO] Found ${packages.length} package(s): ${packages.map((p) => p.displayName).join(', ')}');
    }

    final packageResults = <String, MigrationAnalysisResult>{};
    final allWarnings = <MigrationWarning>[];
    final allErrors = <MigrationError>[];

    for (final package in packages) {
      try {
        final packageDir = Directory(package.path);
        final result = await analyze(
          packageDir,
          skipTests: skipTests,
          additionalIgnores: additionalIgnores,
        );
        packageResults[package.displayName] = result;
      } catch (e, stack) {
        allErrors.add(MigrationError(
          filePath: package.path,
          line: 1,
          message: 'Failed to analyze package "${package.displayName}": $e',
          code: 'PACKAGE_ANALYSIS_ERROR',
        ));

        if (_verbose) {
          stdout.writeln(
              '[ERROR] Failed to analyze package ${package.displayName}: $e');
          stdout.writeln(stack);
        }
      }
    }

    stopwatch.stop();

    if (_verbose) {
      stdout.writeln(
          '[INFO] Monorepo analysis completed in ${stopwatch.elapsedMilliseconds}ms');
    }

    return MonorepoMigrationAnalysisResult(
      rootPath: rootDir.absolute.path,
      timestamp: DateTime.now(),
      isMonorepo: packages.length > 1,
      packages: packages,
      packageResults: packageResults,
      warnings: allWarnings,
      errors: allErrors,
    );
  }
}

/// Result of analyzing a monorepo with multiple packages
class MonorepoMigrationAnalysisResult {
  MonorepoMigrationAnalysisResult({
    required this.rootPath,
    required this.timestamp,
    required this.isMonorepo,
    required this.packages,
    required this.packageResults,
    required this.warnings,
    required this.errors,
  });
  final String rootPath;
  final DateTime timestamp;
  final bool isMonorepo;
  final List<PackageInMonorepo> packages;
  final Map<String, MigrationAnalysisResult> packageResults;
  final List<MigrationWarning> warnings;
  final List<MigrationError> errors;

  /// Get aggregated analysis across all packages
  MigrationAnalysisResult get aggregated {
    final allFiles = <AnalyzedFile>[];
    final allMatches = <PatternMatch>[];
    final allWarnings = <MigrationWarning>[...warnings];
    final allErrors = <MigrationError>[...errors];
    final allPackages = <String>{};

    for (final result in packageResults.values) {
      allFiles.addAll(result.analyzedFiles);
      allMatches.addAll(result.matches);
      allWarnings.addAll(result.warnings);
      allErrors.addAll(result.errors);
      allPackages.addAll(result.importedPackages);
    }

    return MigrationAnalysisResult(
      projectPath: rootPath,
      timestamp: timestamp,
      analyzedFiles: allFiles,
      matches: allMatches,
      warnings: allWarnings,
      errors: allErrors,
      importedPackages: allPackages,
    );
  }

  Map<String, dynamic> toJson() => {
        'rootPath': rootPath,
        'timestamp': timestamp.toIso8601String(),
        'isMonorepo': isMonorepo,
        'packages': packages
            .map((p) => {
                  'path': p.path,
                  'name': p.name,
                  'isApp': p.isApp,
                })
            .toList(),
        'packageResults': {
          for (final entry in packageResults.entries)
            entry.key: entry.value.toJson(),
        },
        'aggregated': aggregated.toJson(),
        'warnings': warnings.map((w) => w.toJson()).toList(),
        'errors': errors.map((e) => e.toJson()).toList(),
      };
}
