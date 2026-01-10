import 'dart:io';
import 'analyzer.dart';
import 'migrator.dart';
import 'report.dart';
import 'patterns.dart';

class MigrationCLI {
  MigrationCLI({bool verbose = false, bool noColor = false})
      : _verbose = verbose,
        _noColor = noColor;
  final bool _verbose;
  final bool _noColor;

  void printDryRunReport(MigrationAnalysisResult analysis) {
    _printHeader('Migration Preview');
    _printProjectInfo(analysis);
    _printSummary(analysis);
    _printChangesByCategory(analysis);
    _printWarnings(analysis);
    _printNextSteps(true);
  }

  void printMigrationResult(MigrationResult result) {
    _printHeader('Migration Complete');

    if (result.dryRun) {
      stdout.writeln('\n⚠️  DRY RUN - No files were modified\n');
      printDryRunReport(result.analysis);
      return;
    }

    _printProjectInfo(result.analysis);
    _printMigrationSummary(result);
    _printBackupInfo(result);
    _printWarnings(result.analysis);
    _printErrors(result.analysis);
    _printChangesApplied(result);
    _printNextSteps(false);
  }

  void printAnalysisReport(MigrationAnalysisResult analysis,
      {bool json = false}) {
    final generator = MigrationReportGenerator(verbose: _verbose);

    if (json) {
      stdout.writeln(generator.generateJsonSummary(
        MigrationResult(
          analysis: analysis,
          appliedChanges: [],
          timestamp: DateTime.now(),
        ),
      ));
    } else {
      stdout.writeln(generator.generateSummaryReport(
        MigrationResult(
          analysis: analysis,
          appliedChanges: [],
          timestamp: DateTime.now(),
        ),
      ));
    }
  }

  void printAnalysisOnly(MigrationAnalysisResult analysis) {
    _printHeader('Migration Analysis');
    _printProjectInfo(analysis);
    _printSummary(analysis);
    _printChangesByCategory(analysis);
    _printMigrationHints(analysis);
    _printWarnings(analysis);
    stdout.writeln('');
    stdout.writeln('${_bold}Next Steps$_reset');
    stdout.writeln('$_gray${'─' * 40}$_reset');
    stdout
        .writeln('Run ${_cyan}dart run locus:migrate$_reset to apply changes.');
    stdout.writeln('Add $_cyan--dry-run$_reset to preview changes first.');
    stdout.writeln('');
  }

  void _printMigrationHints(MigrationAnalysisResult analysis) {
    if (analysis.totalMatches == 0) return;

    stdout.writeln('${_bold}Migration Hints$_reset');
    stdout.writeln('$_gray${'─' * 40}$_reset');

    // Check for removed features
    if (analysis.removedFeaturesCount > 0) {
      stdout.writeln(
          '$_red⚠$_reset  ${analysis.removedFeaturesCount} removed feature(s) detected:');
      stdout.writeln(
          '   These methods no longer exist in v2.0 and require manual replacement.');
    }

    // Check for headless patterns
    final headlessMatches = analysis.matches
        .where(
          (m) => m.patternId.contains('headless'),
        )
        .length;
    if (headlessMatches > 0) {
      stdout.writeln(
          '$_yellow⚠$_reset  $headlessMatches headless callback(s) found:');
      stdout.writeln(
          '   Add @pragma(\'vm:entry-point\') annotation above these functions.');
    }

    // Check for config patterns
    final configMatches = analysis.matches
        .where(
          (m) => m.patternId.contains('config'),
        )
        .length;
    if (configMatches > 0) {
      stdout.writeln('$_cyanℹ$_reset  $configMatches config pattern(s) found:');
      stdout.writeln(
          '   Review LocusConfig for renamed parameters (url→syncUrl, httpTimeout→syncTimeout).');
    }

    // Suggest testing
    if (analysis.autoMigratableCount > 0) {
      stdout.writeln(
          '$_green✓$_reset  ${analysis.autoMigratableCount} pattern(s) can be auto-migrated.');
      stdout.writeln('   Run tests after migration to verify behavior.');
    }

    _printLine();
  }

  void _printHeader(String title) {
    stdout.writeln('\n$_cyan╔${'═' * 58}╗$_reset');
    stdout.writeln(
        '$_cyan║$_reset $_bold$title$_reset${' ' * (56 - title.length)}$_cyan║$_reset');
    stdout.writeln('$_cyan╚${'═' * 58}╝$_reset\n');
  }

  void _printProjectInfo(MigrationAnalysisResult analysis) {
    stdout.writeln('Project: ${analysis.projectPath}');
    stdout.writeln('Generated: ${_formatTimestamp(analysis.timestamp)}');
    _printLine();
  }

  void _printSummary(MigrationAnalysisResult analysis) {
    stdout.writeln('${_bold}Summary$_reset');
    stdout.writeln('$_gray${'─' * 40}$_reset');
    stdout.writeln('Files analyzed: $_bold${analysis.totalFiles}$_reset');
    stdout.writeln(
        'Files with Locus SDK: $_bold${analysis.filesWithLocus}$_reset');
    stdout
        .writeln('Total patterns found: $_bold${analysis.totalMatches}$_reset');
    _printLine();
  }

  void _printMigrationSummary(MigrationResult result) {
    stdout.writeln('${_bold}Summary$_reset');
    stdout.writeln('$_gray${'─' * 40}$_reset');
    stdout.writeln('Files analyzed: ${result.analysis.totalFiles}');
    stdout.writeln('Files with Locus SDK: ${result.analysis.filesWithLocus}');
    stdout.writeln('Total patterns found: ${result.analysis.totalMatches}');
    stdout.writeln(
        'Auto-migratable: $_green${result.analysis.autoMigratableCount}$_reset');
    stdout.writeln(
        'Manual review required: $_yellow${result.analysis.manualReviewCount}$_reset');
    stdout.writeln(
        'Removed features: $_red${result.analysis.removedFeaturesCount}$_reset');
    _printLine();
  }

  void _printBackupInfo(MigrationResult result) {
    if (result.backupPath != null) {
      stdout.writeln(
          '$_green📦 Backup created: ${result.backupPath}/backup.tar.gz$_reset');
      _printLine();
    }
  }

  void _printChangesByCategory(MigrationAnalysisResult analysis) {
    if (analysis.matches.isEmpty) {
      stdout.writeln(
          '$_green✅ No Locus SDK v1.x patterns found - already migrated!$_reset');
      _printLine();
      return;
    }

    stdout.writeln('${_bold}Changes by Category$_reset');
    stdout.writeln('$_gray${'─' * 40}$_reset');

    final byCategory = <MigrationCategory, List<PatternMatch>>{};
    for (final match in analysis.matches) {
      final pattern = MigrationPatternDatabase.allPatterns
          .firstWhere((p) => p.id == match.patternId);
      byCategory.putIfAbsent(pattern.category, () => []).add(match);
    }

    for (final category in MigrationCategory.values) {
      final matches = byCategory[category];
      if (matches != null && matches.isNotEmpty) {
        final icon = _getCategoryIcon(category);
        final color = _getCategoryColor(category);
        stdout.writeln(
            '$icon $color${_getCategoryName(category)}$_reset: ${matches.length}');

        for (final match in matches.take(3)) {
          final shortOriginal = _truncate(match.original, 25);
          final shortReplacement = _truncate(match.replacement, 25);
          stdout.writeln('    $_gray${match.filePath}:${match.line}$_reset');
          stdout.writeln(
              '    $_red$shortOriginal$_reset → $_green$shortReplacement$_reset');
        }

        if (matches.length > 3) {
          stdout.writeln('    $_gray... and ${matches.length - 3} more$_reset');
        }
        _printLine();
      }
    }
  }

  void _printChangesApplied(MigrationResult result) {
    stdout.writeln('${_bold}Changes Applied$_reset');
    stdout.writeln('$_gray${'─' * 40}$_reset');
    stdout.writeln('Files modified: $_bold${result.filesModified}$_reset');
    stdout.writeln('Successful: $_green${result.successfulChanges}$_reset');
    stdout.writeln(
        'Failed: ${result.failedChanges > 0 ? _red : _green}${result.failedChanges}$_reset');
    _printLine();

    if (result.successfulChanges > 0 && _verbose) {
      stdout.writeln('${_bold}Migrated Files:$_reset');
      final files = result.appliedChanges
          .where((c) => c.success)
          .map((c) => c.filePath)
          .toSet();

      for (final file in files) {
        stdout.writeln('  $_green✓$_reset $file');
      }
      _printLine();
    }

    if (result.failedChanges > 0) {
      stdout.writeln('${_bold}Failed Changes:$_reset');
      for (final change in result.appliedChanges.where((c) => !c.success)) {
        stdout.writeln('  $_red✗$_reset ${change.filePath}:${change.line}');
        stdout.writeln('    ${_gray}Reason: ${change.failureReason}$_reset');
      }
      _printLine();
    }
  }

  void _printWarnings(MigrationAnalysisResult analysis) {
    if (analysis.warnings.isEmpty) return;

    stdout.writeln('$_yellow⚠️  Warnings (${analysis.warnings.length})$_reset');
    stdout.writeln('$_gray${'-' * 40}$_reset');

    for (final warning in analysis.warnings.take(10)) {
      stdout.writeln('${warning.filePath}:${warning.line}');
      stdout.writeln('  $_yellow${warning.code}$_reset: ${warning.message}');
      if (warning.suggestion != null) {
        stdout.writeln('  $_gray💡 ${warning.suggestion}$_reset');
      }
    }

    if (analysis.warnings.length > 10) {
      stdout.writeln(
          '  $_gray... and ${analysis.warnings.length - 10} more$_reset');
    }
    _printLine();
  }

  void _printErrors(MigrationAnalysisResult analysis) {
    if (analysis.errors.isEmpty) return;

    stdout.writeln('$_red❌ Errors (${analysis.errors.length})$_reset');
    stdout.writeln('$_gray${'-' * 40}$_reset');

    for (final error in analysis.errors) {
      stdout.writeln('${error.filePath}:${error.line}');
      stdout.writeln('  $_red${error.code}$_reset: ${error.message}');
    }
    _printLine();
  }

  void _printNextSteps(bool isDryRun) {
    stdout.writeln('${_bold}Next Steps$_reset');
    stdout.writeln('$_gray${'-' * 40}$_reset');

    if (isDryRun) {
      stdout.writeln('1. Review the changes above');
      stdout.writeln(
          '2. Run ${_green}dart run locus:migrate$_reset to apply changes');
      stdout.writeln(
          '3. Or run ${_green}dart run locus:migrate --backup$_reset to create a backup first');
    } else {
      stdout.writeln('1. Run your tests to verify migration');
      stdout.writeln(
          '2. Build your app: ${_green}flutter build apk$_reset or ${_green}flutter build ios$_reset');
      stdout.writeln('3. If issues arise, restore from backup:');
      stdout
          .writeln('   ${_gray}tar -xzf .locus/backup/*/backup.tar.gz$_reset');
    }

    _printLine();
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.year}-${_pad(timestamp.month)}-${_pad(timestamp.day)} '
        '${_pad(timestamp.hour)}:${_pad(timestamp.minute)}:${_pad(timestamp.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  void _printLine() {
    stdout.writeln('');
  }

  String _truncate(String s, int maxLength) {
    if (s.length <= maxLength) return s;
    return '${s.substring(0, maxLength - 3)}...';
  }

  String _getCategoryIcon(MigrationCategory category) {
    switch (category) {
      case MigrationCategory.location:
        return '📍';
      case MigrationCategory.geofencing:
        return '🗺️';
      case MigrationCategory.privacy:
        return '🔒';
      case MigrationCategory.trips:
        return '🚗';
      case MigrationCategory.sync:
        return '🔄';
      case MigrationCategory.battery:
        return '🔋';
      case MigrationCategory.diagnostics:
        return '🔍';
      case MigrationCategory.removed:
        return '🗑️';
    }
  }

  String _getCategoryName(MigrationCategory category) {
    switch (category) {
      case MigrationCategory.location:
        return 'Location';
      case MigrationCategory.geofencing:
        return 'Geofencing';
      case MigrationCategory.privacy:
        return 'Privacy';
      case MigrationCategory.trips:
        return 'Trips';
      case MigrationCategory.sync:
        return 'Sync';
      case MigrationCategory.battery:
        return 'Battery';
      case MigrationCategory.diagnostics:
        return 'Diagnostics';
      case MigrationCategory.removed:
        return 'Removed Features';
    }
  }

  String _getCategoryColor(MigrationCategory category) {
    switch (category) {
      case MigrationCategory.location:
        return _blue;
      case MigrationCategory.geofencing:
        return _purple;
      case MigrationCategory.privacy:
        return _green;
      case MigrationCategory.trips:
        return _orange;
      case MigrationCategory.sync:
        return _cyan;
      case MigrationCategory.battery:
        return _yellow;
      case MigrationCategory.diagnostics:
        return _magenta;
      case MigrationCategory.removed:
        return _red;
    }
  }

  void info(String message) {
    if (_verbose) {
      stdout.writeln('$_gray[INFO] $message$_reset');
    }
  }

  void warn(String message) {
    stdout.writeln('$_yellow[WARN] $message$_reset');
  }

  void error(String message) {
    stdout.writeln('$_red[ERROR] $message$_reset');
  }

  void success(String message) {
    stdout.writeln('$_green[OK] $message$_reset');
  }

  void printMonorepoMigrationResult(MonorepoMigrationResult result) {
    _printHeader('Monorepo Migration Complete');

    if (result.dryRun) {
      stdout.writeln('\n$_yellow⚠️  DRY RUN - No files were modified$_reset\n');
    }

    // Print monorepo detection info
    stdout.writeln('${_bold}Workspace Structure$_reset');
    stdout.writeln('$_gray${'─' * 40}$_reset');
    stdout.writeln('Root: ${result.analysis.rootPath}');
    stdout.writeln(
        'Type: ${result.analysis.isMonorepo ? 'Monorepo' : 'Single Package'}');
    stdout.writeln('Total packages: ${result.analysis.packages.length}');
    _printLine();

    // Print per-package results
    stdout.writeln('${_bold}Package Analysis$_reset');
    stdout.writeln('$_gray${'─' * 40}$_reset');

    for (final package in result.analysis.packages) {
      final icon = package.isApp ? '📱' : '📦';
      final typeLabel = package.isApp ? 'app' : 'package';
      stdout.writeln('$icon $_cyan${package.name}$_reset ($typeLabel)');
      stdout.writeln('   ${_gray}Path: ${package.path}$_reset');

      if (result.packageResults.containsKey(package.displayName)) {
        final packageResult = result.packageResults[package.displayName]!;
        final analysis = packageResult.analysis;

        if (analysis.totalMatches > 0) {
          stdout.writeln('   Patterns found: ${analysis.totalMatches}');
          stdout.writeln(
              '   Auto-migratable: $_green${analysis.autoMigratableCount}$_reset');
          if (analysis.manualReviewCount > 0) {
            stdout.writeln(
                '   Manual review: $_yellow${analysis.manualReviewCount}$_reset');
          }
          if (analysis.removedFeaturesCount > 0) {
            stdout.writeln(
                '   Removed features: $_red${analysis.removedFeaturesCount}$_reset');
          }
          if (!result.dryRun) {
            stdout.writeln(
                '   Changes applied: $_green${packageResult.successfulChanges}$_reset');
            if (packageResult.failedChanges > 0) {
              stdout.writeln(
                  '   ${_red}Failed: ${packageResult.failedChanges}$_reset');
            }
          }
        } else {
          stdout.writeln('   ${_gray}No Locus patterns found$_reset');
        }
      } else {
        stdout.writeln('   ${_gray}Not analyzed$_reset');
      }
      stdout.writeln('');
    }

    // Print aggregated summary
    final aggregated = result.analysis.aggregated;
    stdout.writeln('${_bold}Aggregated Summary$_reset');
    stdout.writeln('$_gray${'─' * 40}$_reset');
    stdout.writeln('Total files analyzed: ${aggregated.totalFiles}');
    stdout.writeln('Files with Locus SDK: ${aggregated.filesWithLocus}');
    stdout.writeln('Total patterns found: ${aggregated.totalMatches}');
    stdout.writeln(
        'Auto-migratable: $_green${aggregated.autoMigratableCount}$_reset');
    if (aggregated.manualReviewCount > 0) {
      stdout.writeln(
          'Manual review required: $_yellow${aggregated.manualReviewCount}$_reset');
    }
    if (aggregated.removedFeaturesCount > 0) {
      stdout.writeln(
          'Removed features: $_red${aggregated.removedFeaturesCount}$_reset');
    }

    if (!result.dryRun) {
      _printLine();
      stdout.writeln('${_bold}Migration Results$_reset');
      stdout.writeln('$_gray${'─' * 40}$_reset');
      stdout.writeln('Files modified: ${result.filesModified}');
      stdout.writeln(
          'Successful changes: $_green${result.successfulChanges}$_reset');
      if (result.failedChanges > 0) {
        stdout.writeln('Failed changes: $_red${result.failedChanges}$_reset');
      }
    }

    _printWarnings(aggregated);
    _printNextSteps(result.dryRun);
  }

  // ANSI escape codes - respect _noColor setting
  String get _reset => _noColor ? '' : '\x1B[0m';
  String get _bold => _noColor ? '' : '\x1B[1m';
  String get _gray => _noColor ? '' : '\x1B[90m';
  String get _red => _noColor ? '' : '\x1B[31m';
  String get _green => _noColor ? '' : '\x1B[32m';
  String get _yellow => _noColor ? '' : '\x1B[33m';
  String get _blue => _noColor ? '' : '\x1B[34m';
  String get _purple => _noColor ? '' : '\x1B[35m';
  String get _cyan => _noColor ? '' : '\x1B[36m';
  String get _magenta => _noColor ? '' : '\x1B[35m';
  String get _orange => _noColor ? '' : '\x1B[38;5;208m';
}
