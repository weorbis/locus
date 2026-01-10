import 'dart:io';
import 'package:args/command_runner.dart';

import '../migrate/analyzer.dart';
import '../migrate/migrator.dart';
import '../migrate/cli.dart';
import '../migrate/monorepo.dart';

class MigrateCommand extends Command<void> {
  MigrateCommand() {
    argParser
      ..addFlag(
        'dry-run',
        abbr: 'n',
        help: 'Preview changes without modifying files',
        defaultsTo: false,
      )
      ..addFlag(
        'backup',
        abbr: 'b',
        help: 'Create backup before migrating',
        defaultsTo: true,
      )
      ..addOption(
        'path',
        abbr: 'p',
        help: 'Path to project (defaults to current directory)',
        defaultsTo: '.',
      )
      ..addOption(
        'format',
        abbr: 'f',
        help: 'Output format',
        allowed: ['text', 'json'],
        defaultsTo: 'text',
      )
      ..addFlag(
        'verbose',
        abbr: 'v',
        help: 'Show detailed output',
        defaultsTo: false,
      )
      ..addFlag(
        'skip-tests',
        help: 'Skip test files',
        defaultsTo: false,
      )
      ..addFlag(
        'no-color',
        help: 'Disable colored output',
        defaultsTo: false,
      )
      ..addFlag(
        'help',
        abbr: 'h',
        help: 'Show this help message',
        defaultsTo: false,
      )
      ..addFlag(
        'rollback',
        abbr: 'r',
        help: 'Restore from the most recent backup',
        defaultsTo: false,
      )
      ..addFlag(
        'analyze-only',
        help: 'Only analyze without showing migration suggestions',
        defaultsTo: false,
      )
      ..addFlag(
        'interactive',
        abbr: 'i',
        help: 'Interactive mode - confirm each change (not yet implemented)',
        defaultsTo: false,
      )
      ..addMultiOption(
        'ignore-pattern',
        help: 'Pattern IDs to ignore during migration',
        valueHelp: 'pattern-id',
      )
      ..addMultiOption(
        'only-category',
        help:
            'Only migrate specific categories (location, geofencing, privacy, trips, sync, battery, diagnostics)',
        valueHelp: 'category',
      );
  }
  @override
  final name = 'migrate';

  @override
  final description = 'Migrate Locus SDK from v1.x to v2.0';

  @override
  final aliases = ['m', 'upgrade'];

  @override
  String get invocation {
    return '${runner?.executableName} $name [options]';
  }

  @override
  Future<void> run() async {
    final results = argResults;
    if (results == null) {
      stderr.write('Error: Could not parse arguments\n');
      exit(1);
    }

    final verbose = results['verbose'] as bool;
    final dryRun = results['dry-run'] as bool;
    final createBackup = results['backup'] as bool;
    final path = results['path'] as String;
    final format = results['format'] as String;
    final skipTests = results['skip-tests'] as bool;
    final noColor = results['no-color'] as bool;
    final showHelp = results['help'] as bool;
    final rollback = results['rollback'] as bool;
    final analyzeOnly = results['analyze-only'] as bool;
    final ignorePatterns = (results['ignore-pattern'] as List<String>).toSet();
    final onlyCategories = (results['only-category'] as List<String>).toSet();

    if (showHelp) {
      stdout.writeln(usage);
      return;
    }

    final projectDir = Directory(path);

    if (!projectDir.existsSync()) {
      stderr.write('Error: Directory not found: $path\n');
      exit(1);
    }

    final cli = MigrationCLI(verbose: verbose, noColor: noColor);

    // Handle rollback
    if (rollback) {
      await _handleRollback(projectDir, cli, verbose);
      return;
    }

    final analyzer = MigrationAnalyzer(
      verbose: verbose,
      ignoredPatterns: ignorePatterns,
      onlyCategories: onlyCategories.isNotEmpty ? onlyCategories : null,
    );
    final migrator = MigrationMigrator(analyzer: analyzer, verbose: verbose);

    try {
      // Detect monorepo structure and Locus usage
      final detection = await MonorepoDetector.detectMonorepo(projectDir);

      if (detection.isMonorepo) {
        _printMonorepoDetection(cli, detection, verbose);

        if (!detection.hasLocusUsage) {
          cli.warn('No packages with Locus SDK usage detected.');
          cli.info(
              'Migration will still scan all packages for any Locus patterns.');
        }

        final result = await migrator.migrateMonorepo(
          rootDir: projectDir,
          dryRun: analyzeOnly || dryRun,
          createBackup: createBackup && !analyzeOnly,
          skipTests: skipTests,
        );

        if (format == 'json') {
          stdout.writeln(_generateMonorepoJsonOutput(result));
        } else {
          if (analyzeOnly) {
            cli.printAnalysisOnly(result.analysis.aggregated);
          } else {
            cli.printMonorepoMigrationResult(result);
          }
        }

        final exitCode = _determineMonorepoExitCode(result);
        exit(exitCode);
      } else {
        cli.info('Single package detected. Starting migration analysis...');

        final result = await migrator.migrate(
          projectDir: projectDir,
          dryRun: analyzeOnly || dryRun,
          createBackup: createBackup && !analyzeOnly,
          skipTests: skipTests,
        );

        if (format == 'json') {
          stdout.writeln(_generateJsonOutput(result));
        } else {
          if (analyzeOnly) {
            cli.printAnalysisOnly(result.analysis);
          } else {
            cli.printMigrationResult(result);
          }
        }

        final exitCode = _determineExitCode(result);
        exit(exitCode);
      }
    } catch (e, stack) {
      cli.error('Migration failed: $e');
      if (verbose) {
        stderr.write('$stack\n');
      }
      exit(1);
    }
  }

  Future<void> _handleRollback(
    Directory projectDir,
    MigrationCLI cli,
    bool verbose,
  ) async {
    final backupDir = Directory('${projectDir.path}/.locus/backup');
    if (!backupDir.existsSync()) {
      cli.error('No backup directory found at ${backupDir.path}');
      cli.info('Make sure you have run a migration with --backup enabled.');
      exit(1);
    }

    // Find most recent backup
    final backups = await backupDir.list().toList();
    if (backups.isEmpty) {
      cli.error('No backups found in ${backupDir.path}');
      exit(1);
    }

    // Sort by name (which includes timestamp)
    backups.sort((a, b) => b.path.compareTo(a.path));
    final latestBackup = backups.first;

    cli.info('Found backup: ${latestBackup.path}');
    cli.warn(
        'This will restore your project to the state before the last migration.');

    final migrator = MigrationMigrator(verbose: verbose);
    final success = await migrator.rollback(latestBackup.path);

    if (success) {
      cli.success('Successfully restored from backup');
      exit(0);
    } else {
      cli.error('Failed to restore from backup');
      exit(1);
    }
  }

  void _printMonorepoDetection(
    MigrationCLI cli,
    MonorepoDetectionResult detection,
    bool verbose,
  ) {
    cli.info('Monorepo detected with ${detection.totalPackages} packages');
    if (detection.hasLocusUsage) {
      cli.info('${detection.locusPackageCount} package(s) use Locus SDK');
    }
    if (verbose) {
      for (final package in detection.packages) {
        final locusTag = package.usesLocus ? ' [uses Locus]' : '';
        cli.info('  - ${package.displayName}$locusTag');
      }
    }
  }

  String _generateJsonOutput(MigrationResult result) {
    final Map<String, dynamic> output = {
      'dryRun': result.dryRun,
      'timestamp': result.timestamp.toIso8601String(),
      'summary': {
        'filesAnalyzed': result.analysis.totalFiles,
        'filesWithLocus': result.analysis.filesWithLocus,
        'totalPatterns': result.analysis.totalMatches,
        'autoMigratable': result.analysis.autoMigratableCount,
        'manualReview': result.analysis.manualReviewCount,
        'removedFeatures': result.analysis.removedFeaturesCount,
        'filesModified': result.filesModified,
        'successfulChanges': result.successfulChanges,
        'failedChanges': result.failedChanges,
      },
      'backupPath': result.backupPath,
      'matchesByCategory': result.analysis.matchesByCategory,
      'warnings': result.analysis.warnings.map((w) => w.toJson()).toList(),
      'errors': result.analysis.errors.map((e) => e.toJson()).toList(),
    };

    return _formatJson(output);
  }

  String _formatJson(Map<String, dynamic> data) {
    try {
      return _jsonEncode(data, 0);
    } catch (e) {
      return data.toString();
    }
  }

  String _jsonEncode(Map<String, dynamic> data, int indent) {
    final buffer = StringBuffer();
    final spaces = '  ' * indent;
    final nextSpaces = '  ' * (indent + 1);

    buffer.write('{\n');

    final entries = data.entries.toList();
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];
      buffer.write('$nextSpaces"${entry.key}": ');

      final value = entry.value;
      if (value is Map<String, dynamic>) {
        buffer.write(_jsonEncode(value, indent + 1));
      } else if (value is List) {
        buffer.write(_jsonEncodeList(value, indent + 1));
      } else if (value is String) {
        buffer.write('"${value.replaceAll('"', '\\"')}"');
      } else if (value is bool || value is num) {
        buffer.write(value.toString());
      } else if (value == null) {
        buffer.write('null');
      } else {
        buffer.write('"${value.toString()}"');
      }

      if (i < entries.length - 1) {
        buffer.write(',');
      }
      buffer.write('\n');
    }

    buffer.write('$spaces}');
    return buffer.toString();
  }

  String _jsonEncodeList(List<dynamic> list, int indent) {
    if (list.isEmpty) return '[]';

    final buffer = StringBuffer();
    final spaces = '  ' * indent;
    final nextSpaces = '  ' * (indent + 1);

    buffer.write('[\n');

    for (int i = 0; i < list.length; i++) {
      final value = list[i];
      buffer.write(nextSpaces);

      if (value is Map<String, dynamic>) {
        buffer.write(_jsonEncode(value, indent + 1));
      } else if (value is List) {
        buffer.write(_jsonEncodeList(value, indent + 1));
      } else if (value is String) {
        buffer.write('"${value.replaceAll('"', '\\"')}"');
      } else if (value is bool || value is num) {
        buffer.write(value.toString());
      } else if (value == null) {
        buffer.write('null');
      } else {
        buffer.write('"${value.toString()}"');
      }

      if (i < list.length - 1) {
        buffer.write(',');
      }
      buffer.write('\n');
    }

    buffer.write('$spaces]');
    return buffer.toString();
  }

  int _determineExitCode(MigrationResult result) {
    if (result.failedChanges > 0) {
      return 1;
    }

    if (result.analysis.manualReviewCount > 0 && !result.dryRun) {
      return 0;
    }

    return 0;
  }

  String _generateMonorepoJsonOutput(MonorepoMigrationResult result) {
    final Map<String, dynamic> output = result.toJson();
    return _formatJson(output);
  }

  int _determineMonorepoExitCode(MonorepoMigrationResult result) {
    if (result.failedChanges > 0) {
      return 1;
    }

    final manualReviewCount = result.analysis.packageResults.values
        .fold(0, (sum, r) => sum + r.manualReviewCount);

    if (manualReviewCount > 0 && !result.dryRun) {
      return 0;
    }

    return 0;
  }
}
