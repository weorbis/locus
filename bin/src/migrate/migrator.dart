import 'dart:io';
import 'analyzer.dart';
import 'patterns.dart';

class AppliedChange {
  final String filePath;
  final int line;
  final String patternId;
  final String original;
  final String replacement;
  final bool success;
  final String? failureReason;

  AppliedChange({
    required this.filePath,
    required this.line,
    required this.patternId,
    required this.original,
    required this.replacement,
    required this.success,
    this.failureReason,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'line': line,
        'patternId': patternId,
        'original': original,
        'replacement': replacement,
        'success': success,
        'failureReason': failureReason,
      };
}

class MigrationResult {
  final MigrationAnalysisResult analysis;
  final List<AppliedChange> appliedChanges;
  final String? backupPath;
  final bool dryRun;
  final DateTime timestamp;

  MigrationResult({
    required this.analysis,
    required this.appliedChanges,
    this.backupPath,
    this.dryRun = false,
    required this.timestamp,
  });

  int get successfulChanges => appliedChanges.where((c) => c.success).length;
  int get failedChanges => appliedChanges.where((c) => !c.success).length;
  int get filesModified => appliedChanges.map((c) => c.filePath).toSet().length;

  Map<String, dynamic> toJson() => {
        'dryRun': dryRun,
        'timestamp': timestamp.toIso8601String(),
        'backupPath': backupPath,
        'summary': {
          'totalMatches': analysis.totalMatches,
          'successfulChanges': successfulChanges,
          'failedChanges': failedChanges,
          'filesModified': filesModified,
        },
        'analysis': analysis.toJson(),
        'appliedChanges': appliedChanges.map((c) => c.toJson()).toList(),
      };
}

class MigrationMigrator {
  final MigrationAnalyzer _analyzer;
  final bool _verbose;

  MigrationMigrator({
    MigrationAnalyzer? analyzer,
    bool verbose = false,
  })  : _analyzer = analyzer ?? MigrationAnalyzer(),
        _verbose = verbose;

  Future<MigrationResult> migrate({
    required Directory projectDir,
    required bool dryRun,
    required bool createBackup,
    bool skipTests = false,
    Set<String>? additionalIgnores,
  }) async {
    final timestamp = DateTime.now();

    if (_verbose) {
      print('[INFO] Starting migration of ${projectDir.path}');
      print('[INFO] Dry run: $dryRun, Create backup: $createBackup');
    }

    final analysis = await _analyzer.analyze(
      projectDir,
      skipTests: skipTests,
      additionalIgnores: additionalIgnores,
    );

    if (dryRun) {
      if (_verbose) {
        print('[INFO] Dry run - no files will be modified');
      }
      return MigrationResult(
        analysis: analysis,
        appliedChanges: [],
        dryRun: true,
        timestamp: timestamp,
      );
    }

    String? backupPath;
    if (createBackup) {
      backupPath = await _createBackup(projectDir, timestamp);
    }

    final appliedChanges = await _applyMigrations(analysis, projectDir);

    if (_verbose) {
      print('[INFO] Migration complete');
      print(
          '[INFO] Applied ${appliedChanges.where((c) => c.success).length} changes');
      print('[INFO] Failed: ${appliedChanges.where((c) => !c.success).length}');
      if (backupPath != null) {
        print('[INFO] Backup created at: $backupPath');
      }
    }

    return MigrationResult(
      analysis: analysis,
      appliedChanges: appliedChanges,
      backupPath: backupPath,
      dryRun: false,
      timestamp: timestamp,
    );
  }

  Future<String?> _createBackup(
      Directory projectDir, DateTime timestamp) async {
    final backupDir = Directory(
        '${projectDir.path}/.locus/backup/${_timestampToPath(timestamp)}');

    try {
      await backupDir.create(recursive: true);

      final tarArgs = [
        '-czf',
        '${backupDir.path}/backup.tar.gz',
        '-C',
        projectDir.path,
        '.',
      ];

      final result = await Process.run(
        'tar',
        tarArgs,
        workingDirectory: projectDir.path,
      );

      if (result.exitCode != 0) {
        stderr.write('[WARNING] Failed to create backup: ${result.stderr}\n');
        return null;
      }

      if (_verbose) {
        print('[INFO] Backup created at ${backupDir.path}/backup.tar.gz');
      }

      return backupDir.path;
    } catch (e) {
      stderr.write('[WARNING] Failed to create backup: $e\n');
      return null;
    }
  }

  String _timestampToPath(DateTime timestamp) {
    return timestamp
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
  }

  Future<List<AppliedChange>> _applyMigrations(
    MigrationAnalysisResult analysis,
    Directory projectDir,
  ) async {
    final appliedChanges = <AppliedChange>[];

    final changesByFile = <String, List<PatternMatch>>{};
    for (final match in analysis.matches) {
      changesByFile.putIfAbsent(match.filePath, () => []).add(match);
    }

    for (final entry in changesByFile.entries) {
      final filePath = entry.key;
      final matches = entry.value;

      try {
        final file = File(filePath);
        var content = await file.readAsString();

        final sortedMatches = matches
            .map((m) => {
                  'match': m,
                  'adjustedOffset': m.column +
                      _calculateOffsetAdjustment(
                        matches
                            .where(
                                (x) => x.line == m.line && x.column < m.column)
                            .toList(),
                        m.original.length,
                      ),
                })
            .toList()
          ..sort((a, b) => (b['adjustedOffset'] as int)
              .compareTo(a['adjustedOffset'] as int));

        for (final item in sortedMatches) {
          final match = item['match'] as PatternMatch;
          final adjustedOffset = item['adjustedOffset'] as int;

          final originalText = content.substring(
            adjustedOffset,
            adjustedOffset + match.original.length,
          );

          if (originalText == match.original) {
            final pattern = MigrationPatternDatabase.allPatterns
                .firstWhere((p) => p.id == match.patternId);

            final replacement = _buildReplacement(match, pattern);

            content = content.replaceRange(
              adjustedOffset,
              adjustedOffset + match.original.length,
              replacement,
            );

            totalOffsetAdjustment += replacement.length - match.original.length;

            appliedChanges.add(AppliedChange(
              filePath: filePath,
              line: match.line,
              patternId: match.patternId,
              original: match.original,
              replacement: replacement,
              success: true,
            ));

            if (_verbose) {
              print('[MIGRATED] $filePath:${match.line}');
              print('    ${match.original} → $replacement');
            }
          } else {
            appliedChanges.add(AppliedChange(
              filePath: filePath,
              line: match.line,
              patternId: match.patternId,
              original: match.original,
              replacement: '',
              success: false,
              failureReason: 'Text mismatch during replacement',
            ));

            stderr.write('[ERROR] $filePath:${match.line} - Text mismatch\n');
          }
        }

        await file.writeAsString(content);

        if (_verbose) {
          print('[INFO] Updated $filePath (${matches.length} changes)');
        }
      } catch (e, stack) {
        appliedChanges.add(AppliedChange(
          filePath: filePath,
          line: 1,
          patternId: 'unknown',
          original: '',
          replacement: '',
          success: false,
          failureReason: 'Exception: $e',
        ));

        stderr.write('[ERROR] Failed to update $filePath: $e\n');
        if (_verbose) {
          stderr.write('$stack\n');
        }
      }
    }

    return appliedChanges;
  }

  int _calculateOffsetAdjustment(
      List<PatternMatch> previousMatches, int currentLength) {
    int adjustment = 0;
    for (final prev in previousMatches) {
      adjustment += prev.replacement.length - prev.original.length;
    }
    return adjustment;
  }

  String _buildReplacement(PatternMatch match, MigrationPattern pattern) {
    String replacement = pattern.toPatternTemplate;

    final matchGroups = <String, String>{};
    final regexMatch = RegExp(pattern.fromPattern).firstMatch(match.original);
    if (regexMatch != null) {
      for (int i = 1; i <= regexMatch.groupCount; i++) {
        matchGroups['$i'] = regexMatch.group(i) ?? '';
      }
    }

    for (final entry in matchGroups.entries) {
      replacement = replacement.replaceAll('\$${entry.key}', entry.value);
    }

    return replacement;
  }

  Future<bool> rollback(String backupPath) async {
    final backupFile = File('$backupPath/backup.tar.gz');

    if (!await backupFile.exists()) {
      stderr.write('[ERROR] Backup file not found: $backupPath\n');
      return false;
    }

    try {
      final result = await Process.run(
        'tar',
        ['-xzf', backupFile.path, '-C', Directory(backupPath).parent.path],
      );

      if (result.exitCode != 0) {
        stderr.write('[ERROR] Failed to restore backup: ${result.stderr}\n');
        return false;
      }

      if (_verbose) {
        print('[INFO] Successfully restored from $backupPath');
      }

      return true;
    } catch (e) {
      stderr.write('[ERROR] Failed to restore backup: $e\n');
      return false;
    }
  }

  /// Migrates a monorepo with multiple packages
  Future<MonorepoMigrationResult> migrateMonorepo({
    required Directory rootDir,
    required bool dryRun,
    required bool createBackup,
    bool skipTests = false,
    Set<String>? additionalIgnores,
  }) async {
    final timestamp = DateTime.now();

    if (_verbose) {
      print('[INFO] Starting monorepo migration of ${rootDir.path}');
      print('[INFO] Dry run: $dryRun, Create backup: $createBackup');
    }

    final analysis = await _analyzer.analyzeMonorepo(
      rootDir,
      skipTests: skipTests,
      additionalIgnores: additionalIgnores,
    );

    if (dryRun) {
      if (_verbose) {
        print('[INFO] Dry run - no files will be modified');
      }
      return MonorepoMigrationResult(
        analysis: analysis,
        packageResults: {},
        dryRun: true,
        timestamp: timestamp,
      );
    }

    String? backupPath;
    if (createBackup) {
      backupPath = await _createBackup(rootDir, timestamp);
    }

    final packageResults = <String, MigrationResult>{};

    for (final entry in analysis.packageResults.entries) {
      final packageName = entry.key;
      final packageAnalysis = entry.value;

      // Find the package directory
      final packageDir = Directory(packageAnalysis.projectPath);
      if (!await packageDir.exists()) {
        continue;
      }

      if (_verbose) {
        print('[INFO] Migrating package: $packageName');
      }

      final appliedChanges =
          await _applyMigrations(packageAnalysis, packageDir);

      packageResults[packageName] = MigrationResult(
        analysis: packageAnalysis,
        appliedChanges: appliedChanges,
        backupPath: backupPath,
        dryRun: false,
        timestamp: timestamp,
      );
    }

    if (_verbose) {
      print('[INFO] Monorepo migration complete');
      final totalSuccessful =
          packageResults.values.fold(0, (sum, r) => sum + r.successfulChanges);
      final totalFailed =
          packageResults.values.fold(0, (sum, r) => sum + r.failedChanges);
      print('[INFO] Applied $totalSuccessful changes');
      print('[INFO] Failed: $totalFailed');
      if (backupPath != null) {
        print('[INFO] Backup created at: $backupPath');
      }
    }

    return MonorepoMigrationResult(
      analysis: analysis,
      packageResults: packageResults,
      dryRun: false,
      timestamp: timestamp,
    );
  }
}

/// Result of migrating a monorepo
class MonorepoMigrationResult {
  final MonorepoMigrationAnalysisResult analysis;
  final Map<String, MigrationResult> packageResults;
  final bool dryRun;
  final DateTime timestamp;

  MonorepoMigrationResult({
    required this.analysis,
    required this.packageResults,
    required this.dryRun,
    required this.timestamp,
  });

  int get successfulChanges =>
      packageResults.values.fold(0, (sum, r) => sum + r.successfulChanges);

  int get failedChanges =>
      packageResults.values.fold(0, (sum, r) => sum + r.failedChanges);

  int get filesModified => packageResults.values.fold(<String>{}, (set, r) {
        set.addAll(r.appliedChanges.map((c) => c.filePath));
        return set;
      }).length;

  Map<String, dynamic> toJson() => {
        'dryRun': dryRun,
        'timestamp': timestamp.toIso8601String(),
        'summary': {
          'packages': packageResults.length,
          'filesModified': filesModified,
          'successfulChanges': successfulChanges,
          'failedChanges': failedChanges,
        },
        'analysis': analysis.toJson(),
        'packageResults': {
          for (final entry in packageResults.entries)
            entry.key: entry.value.toJson(),
        },
      };
}
