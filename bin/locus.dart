/// Locus CLI - Main Entry Point
///
/// A command-line tool for Locus SDK management.
///
/// Usage:
///   `dart run locus [command] [options]`
///
/// Commands:
///   setup     Configure native permissions and dependencies
///   doctor    Diagnose configuration and platform issues
///   migrate   Migrate from Locus v1.x to v2.0
///
/// Run a command with --help for more details:
///   dart run locus migrate --help
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import 'src/commands/migrate_command.dart';

const _version = '2.0.0';

class LocusCLI extends CommandRunner<void> {
  LocusCLI() : super('locus', 'Locus SDK CLI - v$_version') {
    argParser.addFlag(
      'version',
      abbr: 'v',
      negatable: false,
      help: 'Show version',
    );
    argParser.addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show help',
    );

    addCommand(SetupPlaceholderCommand());
    addCommand(DoctorPlaceholderCommand());
    addCommand(MigrateCommand());
  }
}

class SetupPlaceholderCommand extends Command<void> {
  SetupPlaceholderCommand() {
    argParser.addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show help',
    );
  }
  @override
  final name = 'setup';

  @override
  final description = 'Configure native permissions and dependencies';

  @override
  final aliases = ['init', 'configure'];

  @override
  Future<void> run() async {
    if (argResults?['help'] as bool? ?? false) {
      stdout.writeln('''
Locus Setup v$_version

Configure native permissions and dependencies for Locus SDK.

Usage:
  dart run locus setup [options]

Options:
  --help, -h    Show this help message
  --verbose     Show detailed output

Note: Run 'dart run locus:setup' directly for the full setup command.
''');
      return;
    }

    stdout.writeln('''
╔══════════════════════════════════════════════════════════════╗
║                    Locus SDK - Setup                         ║
╠══════════════════════════════════════════════════════════════╣

This is a placeholder. Run 'dart run locus:setup' for the full setup.

''');
  }
}

class DoctorPlaceholderCommand extends Command<void> {
  DoctorPlaceholderCommand() {
    argParser.addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show help',
    );
  }
  @override
  final name = 'doctor';

  @override
  final description = 'Diagnose configuration and platform issues';

  @override
  final aliases = ['diagnose', 'check'];

  @override
  Future<void> run() async {
    if (argResults?['help'] as bool? ?? false) {
      stdout.writeln('''
Locus Doctor v$_version

Diagnose configuration and platform issues with Locus SDK.

Usage:
  dart run locus doctor [options]

Options:
  --help, -h    Show this help message
  --verbose     Show detailed output

Note: Run 'dart run locus:doctor' directly for the full diagnosis.
''');
      return;
    }

    stdout.writeln('''
╔══════════════════════════════════════════════════════════════╗
║                    Locus SDK - Doctor                        ║
╠══════════════════════════════════════════════════════════════╣

This is a placeholder. Run 'dart run locus:doctor' for the full diagnosis.

''');
  }
}

Future<void> main(List<String> args) async {
  final cli = LocusCLI();

  try {
    if (args.isEmpty || args.first == '--help' || args.first == '-h') {
      stdout.writeln('''
╔══════════════════════════════════════════════════════════════╗
║                    Locus SDK CLI v$_version                     ║
╠══════════════════════════════════════════════════════════════╣
║  A battle-tested background geolocation SDK for Flutter      ║
╠══════════════════════════════════════════════════════════════╣

Usage: dart run locus <command> [options]

Commands:
  setup     Configure native permissions and dependencies
  doctor    Diagnose configuration and platform issues
  migrate   Migrate from Locus v1.x to v2.0

Run a command with --help for more details:
  dart run locus migrate --help

''');
      exit(0);
    }

    await cli.run(args);
  } on UsageException catch (e) {
    stderr.write('$e\n');
    exit(1);
  } catch (e, stack) {
    stderr.write('Error: $e\n');
    if (args.contains('--verbose') || args.contains('-v')) {
      stderr.write('$stack\n');
    }
    exit(1);
  }
}
