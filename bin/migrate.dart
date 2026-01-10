/// Locus CLI - Migrate Command Standalone
///
/// Migrate Locus SDK from v1.x to v2.0
///
/// Usage:
///   `dart run locus:migrate [options]`
///
/// Options:
///   --dry-run       Preview changes without modifying files
///   --backup        Create backup before migrating
///   --path          Project path (defaults to current directory)
///   --format        Output format (text/json)
///   --verbose       Show detailed output
///   --skip-tests    Skip test files
///   --no-color      Disable colored output
///   --help          Show help
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'src/migrate/analyzer.dart';
import 'src/migrate/migrator.dart';
import 'src/migrate/cli.dart';
import 'src/migrate/report.dart';

class MigrateArgsParser {
  final ArgParser _parser = ArgParser()
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
    );

  ArgParser get parser => _parser;

  Map<String, dynamic> parse(List<String> args) {
    final results = _parser.parse(args);
    return {
      'dry-run': results['dry-run'] as bool,
      'backup': results['backup'] as bool,
      'path': results['path'] as String,
      'format': results['format'] as String,
      'verbose': results['verbose'] as bool,
      'skip-tests': results['skip-tests'] as bool,
      'no-color': results['no-color'] as bool,
      'help': results['help'] as bool,
    };
  }

  String get usage => _parser.usage;
}

class MigrateCommandRunner extends Command<void> {
  MigrateCommandRunner() {
    argParser.addFlag(
      'dry-run',
      abbr: 'n',
      help: 'Preview changes without modifying files',
      defaultsTo: false,
    );
    argParser.addFlag(
      'backup',
      abbr: 'b',
      help: 'Create backup before migrating',
      defaultsTo: true,
    );
    argParser.addOption(
      'path',
      abbr: 'p',
      help: 'Path to project (defaults to current directory)',
      defaultsTo: '.',
    );
    argParser.addOption(
      'format',
      abbr: 'f',
      help: 'Output format',
      allowed: ['text', 'json'],
      defaultsTo: 'text',
    );
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Show detailed output',
      defaultsTo: false,
    );
    argParser.addFlag(
      'skip-tests',
      help: 'Skip test files',
      defaultsTo: false,
    );
    argParser.addFlag(
      'no-color',
      help: 'Disable colored output',
      defaultsTo: false,
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

    if (showHelp) {
      stdout.writeln('''Migrate Locus SDK from v1.x to v2.0

Usage:
  dart run locus:migrate [options]

Options:
  -n, --dry-run       Preview changes without modifying files
  -b, --backup        Create backup before migrating (default: true)
  -p, --path          Project path (default: current directory)
  -f, --format        Output format: text|json (default: text)
  -v, --verbose       Show detailed output
      --skip-tests    Skip test files
      --no-color      Disable colored output
  -h, --help          Show this help message

Examples:
  # Preview changes
  dart run locus:migrate --dry-run

  # Run migration with backup
  dart run locus:migrate --backup

  # Migrate a specific project
  dart run locus:migrate --path=/path/to/project

  # JSON output for CI/CD
  dart run locus:migrate --format=json

What gets migrated:
  • Locus.start() → Locus.location.start()
  • Locus.onLocation(cb) → Locus.location.onLocation(cb)
  • Locus.addGeofence(g) → Locus.geofencing.addGeofence(g)
  • ... and 50+ more patterns

Features removed in v2.0:
  • Locus.emailLog() - Use your own email implementation
  • Locus.playSound() - Use flutter_sound package

For more information, see:
  doc/guides/migration.md
''');
      return;
    }

    final projectDir = Directory(path);

    if (!projectDir.existsSync()) {
      stderr.write('Error: Directory not found: $path\n');
      exit(1);
    }

    final cli = MigrationCLI(verbose: verbose, noColor: noColor);
    final analyzer = MigrationAnalyzer(verbose: verbose);
    final migrator = MigrationMigrator(analyzer: analyzer, verbose: verbose);

    try {
      cli.info('Starting migration analysis...');

      final result = await migrator.migrate(
        projectDir: projectDir,
        dryRun: dryRun,
        createBackup: createBackup,
        skipTests: skipTests,
      );

      if (format == 'json') {
        final generator = MigrationReportGenerator(verbose: verbose);
        stdout.writeln(generator.generateJsonSummary(result));
      } else {
        cli.printMigrationResult(result);
      }

      final exitCode = result.failedChanges > 0 ? 1 : 0;
      exit(exitCode);
    } catch (e, stack) {
      stderr.write('Error during migration: $e\n');
      if (verbose) {
        stderr.write('$stack\n');
      }
      exit(1);
    }
  }
}

class StandaloneRunner extends CommandRunner<void> {
  StandaloneRunner()
      : super('locus:migrate', 'Migrate Locus SDK from v1.x to v2.0') {
    addCommand(MigrateCommandRunner());
  }

  @override
  String get invocation {
    return '$executableName [options]';
  }
}

Future<void> main(List<String> args) async {
  final runner = StandaloneRunner();

  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.write('${e.message}\n${e.usage}');
    exit(1);
  } catch (e, stack) {
    stderr.write('Error: $e\n');
    if (args.contains('-v') || args.contains('--verbose')) {
      stderr.write('$stack\n');
    }
    exit(1);
  }
}
