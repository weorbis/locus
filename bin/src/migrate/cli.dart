import 'analyzer.dart';
import 'migrator.dart';
import 'report.dart';
import 'patterns.dart';

class MigrationCLI {
  final bool _verbose;
  final bool _noColor;

  MigrationCLI({bool verbose = false, bool noColor = false})
      : _verbose = verbose,
        _noColor = noColor;

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
      print('\n⚠️  DRY RUN - No files were modified\n');
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
      print(generator.generateJsonSummary(
        MigrationResult(
          analysis: analysis,
          appliedChanges: [],
          timestamp: DateTime.now(),
        ),
      ));
    } else {
      print(generator.generateSummaryReport(
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
    print('');
    print('${_bold}Next Steps${_reset}');
    print('${_gray}${'─' * 40}${_reset}');
    print('Run ${_cyan}dart run locus:migrate${_reset} to apply changes.');
    print('Add ${_cyan}--dry-run${_reset} to preview changes first.');
    print('');
  }

  void _printMigrationHints(MigrationAnalysisResult analysis) {
    if (analysis.totalMatches == 0) return;

    print('${_bold}Migration Hints${_reset}');
    print('${_gray}${'─' * 40}${_reset}');

    // Check for removed features
    if (analysis.removedFeaturesCount > 0) {
      print('${_red}⚠${_reset}  ${analysis.removedFeaturesCount} removed feature(s) detected:');
      print('   These methods no longer exist in v2.0 and require manual replacement.');
    }

    // Check for headless patterns
    final headlessMatches = analysis.matches.where(
      (m) => m.patternId.contains('headless'),
    ).length;
    if (headlessMatches > 0) {
      print('${_yellow}⚠${_reset}  $headlessMatches headless callback(s) found:');
      print('   Add @pragma(\'vm:entry-point\') annotation above these functions.');
    }

    // Check for config patterns
    final configMatches = analysis.matches.where(
      (m) => m.patternId.contains('config'),
    ).length;
    if (configMatches > 0) {
      print('${_cyan}ℹ${_reset}  $configMatches config pattern(s) found:');
      print('   Review LocusConfig for renamed parameters (url→syncUrl, httpTimeout→syncTimeout).');
    }

    // Suggest testing
    if (analysis.autoMigratableCount > 0) {
      print('${_green}✓${_reset}  ${analysis.autoMigratableCount} pattern(s) can be auto-migrated.');
      print('   Run tests after migration to verify behavior.');
    }

    _printLine();
  }

  void _printHeader(String title) {
    print('\n${_cyan}╔${'═' * 58}╗${_reset}');
    print(
        '${_cyan}║${_reset} ${_bold}$title${_reset}${' ' * (56 - title.length)}${_cyan}║${_reset}');
    print('${_cyan}╚${'═' * 58}╝${_reset}\n');
  }

  void _printProjectInfo(MigrationAnalysisResult analysis) {
    print('Project: ${analysis.projectPath}');
    print('Generated: ${_formatTimestamp(analysis.timestamp)}');
    _printLine();
  }

  void _printSummary(MigrationAnalysisResult analysis) {
    print('${_bold}Summary${_reset}');
    print('${_gray}${'─' * 40}${_reset}');
    print('Files analyzed: ${_bold}${analysis.totalFiles}${_reset}');
    print('Files with Locus SDK: ${_bold}${analysis.filesWithLocus}${_reset}');
    print('Total patterns found: ${_bold}${analysis.totalMatches}${_reset}');
    _printLine();
  }

  void _printMigrationSummary(MigrationResult result) {
    print('${_bold}Summary${_reset}');
    print('${_gray}${'─' * 40}${_reset}');
    print('Files analyzed: ${result.analysis.totalFiles}');
    print('Files with Locus SDK: ${result.analysis.filesWithLocus}');
    print('Total patterns found: ${result.analysis.totalMatches}');
    print(
        'Auto-migratable: ${_green}${result.analysis.autoMigratableCount}${_reset}');
    print(
        'Manual review required: ${_yellow}${result.analysis.manualReviewCount}${_reset}');
    print(
        'Removed features: ${_red}${result.analysis.removedFeaturesCount}${_reset}');
    _printLine();
  }

  void _printBackupInfo(MigrationResult result) {
    if (result.backupPath != null) {
      print(
          '${_green}📦 Backup created: ${result.backupPath}/backup.tar.gz${_reset}');
      _printLine();
    }
  }

  void _printChangesByCategory(MigrationAnalysisResult analysis) {
    if (analysis.matches.isEmpty) {
      print(
          '${_green}✅ No Locus SDK v1.x patterns found - already migrated!${_reset}');
      _printLine();
      return;
    }

    print('${_bold}Changes by Category${_reset}');
    print('${_gray}${'─' * 40}${_reset}');

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
        print(
            '$icon ${color}${_getCategoryName(category)}${_reset}: ${matches.length}');

        for (final match in matches.take(3)) {
          final shortOriginal = _truncate(match.original, 25);
          final shortReplacement = _truncate(match.replacement, 25);
          print('    $_gray${match.filePath}:${match.line}$_reset');
          print(
              '    $_red$shortOriginal$_reset → $_green$shortReplacement$_reset');
        }

        if (matches.length > 3) {
          print('    ${_gray}... and ${matches.length - 3} more${_reset}');
        }
        _printLine();
      }
    }
  }

  void _printChangesApplied(MigrationResult result) {
    print('${_bold}Changes Applied${_reset}');
    print('${_gray}${'─' * 40}${_reset}');
    print('Files modified: ${_bold}${result.filesModified}${_reset}');
    print('Successful: ${_green}${result.successfulChanges}${_reset}');
    print(
        'Failed: ${result.failedChanges > 0 ? _red : _green}${result.failedChanges}${_reset}');
    _printLine();

    if (result.successfulChanges > 0 && _verbose) {
      print('${_bold}Migrated Files:${_reset}');
      final files = result.appliedChanges
          .where((c) => c.success)
          .map((c) => c.filePath)
          .toSet();

      for (final file in files) {
        print('  ${_green}✓${_reset} $file');
      }
      _printLine();
    }

    if (result.failedChanges > 0) {
      print('${_bold}Failed Changes:${_reset}');
      for (final change in result.appliedChanges.where((c) => !c.success)) {
        print('  ${_red}✗${_reset} ${change.filePath}:${change.line}');
        print('    ${_gray}Reason: ${change.failureReason}${_reset}');
      }
      _printLine();
    }
  }

  void _printWarnings(MigrationAnalysisResult analysis) {
    if (analysis.warnings.isEmpty) return;

    print('${_yellow}⚠️  Warnings (${analysis.warnings.length})${_reset}');
    print('${_gray}${'-' * 40}${_reset}');

    for (final warning in analysis.warnings.take(10)) {
      print('${warning.filePath}:${warning.line}');
      print('  ${_yellow}${warning.code}${_reset}: ${warning.message}');
      if (warning.suggestion != null) {
        print('  ${_gray}💡 ${warning.suggestion}${_reset}');
      }
    }

    if (analysis.warnings.length > 10) {
      print('  ${_gray}... and ${analysis.warnings.length - 10} more${_reset}');
    }
    _printLine();
  }

  void _printErrors(MigrationAnalysisResult analysis) {
    if (analysis.errors.isEmpty) return;

    print('${_red}❌ Errors (${analysis.errors.length})${_reset}');
    print('${_gray}${'-' * 40}${_reset}');

    for (final error in analysis.errors) {
      print('${error.filePath}:${error.line}');
      print('  ${_red}${error.code}${_reset}: ${error.message}');
    }
    _printLine();
  }

  void _printNextSteps(bool isDryRun) {
    print('${_bold}Next Steps${_reset}');
    print('${_gray}${'-' * 40}${_reset}');

    if (isDryRun) {
      print('1. Review the changes above');
      print('2. Run ${_green}dart run locus:migrate${_reset} to apply changes');
      print(
          '3. Or run ${_green}dart run locus:migrate --backup${_reset} to create a backup first');
    } else {
      print('1. Run your tests to verify migration');
      print(
          '2. Build your app: ${_green}flutter build apk${_reset} or ${_green}flutter build ios${_reset}');
      print('3. If issues arise, restore from backup:');
      print('   ${_gray}tar -xzf .locus/backup/*/backup.tar.gz${_reset}');
    }

    _printLine();
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.year}-${_pad(timestamp.month)}-${_pad(timestamp.day)} '
        '${_pad(timestamp.hour)}:${_pad(timestamp.minute)}:${_pad(timestamp.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  void _printLine() {
    print('');
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
      print('${_gray}[INFO] $message${_reset}');
    }
  }

  void warn(String message) {
    print('${_yellow}[WARN] $message${_reset}');
  }

  void error(String message) {
    print('${_red}[ERROR] $message${_reset}');
  }

  void success(String message) {
    print('${_green}[OK] $message${_reset}');
  }

  void printMonorepoMigrationResult(MonorepoMigrationResult result) {
    _printHeader('Monorepo Migration Complete');

    if (result.dryRun) {
      print('\n${_yellow}⚠️  DRY RUN - No files were modified${_reset}\n');
    }

    // Print monorepo detection info
    print('${_bold}Workspace Structure${_reset}');
    print('${_gray}${'─' * 40}${_reset}');
    print('Root: ${result.analysis.rootPath}');
    print(
        'Type: ${result.analysis.isMonorepo ? 'Monorepo' : 'Single Package'}');
    print('Total packages: ${result.analysis.packages.length}');
    _printLine();

    // Print per-package results
    print('${_bold}Package Analysis${_reset}');
    print('${_gray}${'─' * 40}${_reset}');

    for (final package in result.analysis.packages) {
      final icon = package.isApp ? '📱' : '📦';
      final typeLabel = package.isApp ? 'app' : 'package';
      print('$icon ${_cyan}${package.name}${_reset} ($typeLabel)');
      print('   ${_gray}Path: ${package.path}${_reset}');

      if (result.packageResults.containsKey(package.displayName)) {
        final packageResult = result.packageResults[package.displayName]!;
        final analysis = packageResult.analysis;

        if (analysis.totalMatches > 0) {
          print('   Patterns found: ${analysis.totalMatches}');
          print(
              '   Auto-migratable: ${_green}${analysis.autoMigratableCount}${_reset}');
          if (analysis.manualReviewCount > 0) {
            print(
                '   Manual review: ${_yellow}${analysis.manualReviewCount}${_reset}');
          }
          if (analysis.removedFeaturesCount > 0) {
            print(
                '   Removed features: ${_red}${analysis.removedFeaturesCount}${_reset}');
          }
          if (!result.dryRun) {
            print(
                '   Changes applied: ${_green}${packageResult.successfulChanges}${_reset}');
            if (packageResult.failedChanges > 0) {
              print(
                  '   ${_red}Failed: ${packageResult.failedChanges}${_reset}');
            }
          }
        } else {
          print('   ${_gray}No Locus patterns found${_reset}');
        }
      } else {
        print('   ${_gray}Not analyzed${_reset}');
      }
      print('');
    }

    // Print aggregated summary
    final aggregated = result.analysis.aggregated;
    print('${_bold}Aggregated Summary${_reset}');
    print('${_gray}${'─' * 40}${_reset}');
    print('Total files analyzed: ${aggregated.totalFiles}');
    print('Files with Locus SDK: ${aggregated.filesWithLocus}');
    print('Total patterns found: ${aggregated.totalMatches}');
    print(
        'Auto-migratable: ${_green}${aggregated.autoMigratableCount}${_reset}');
    if (aggregated.manualReviewCount > 0) {
      print(
          'Manual review required: ${_yellow}${aggregated.manualReviewCount}${_reset}');
    }
    if (aggregated.removedFeaturesCount > 0) {
      print(
          'Removed features: ${_red}${aggregated.removedFeaturesCount}${_reset}');
    }

    if (!result.dryRun) {
      _printLine();
      print('${_bold}Migration Results${_reset}');
      print('${_gray}${'─' * 40}${_reset}');
      print('Files modified: ${result.filesModified}');
      print(
          'Successful changes: ${_green}${result.successfulChanges}${_reset}');
      if (result.failedChanges > 0) {
        print('Failed changes: ${_red}${result.failedChanges}${_reset}');
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
