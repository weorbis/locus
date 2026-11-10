/// Replays routes through Android emulator or iOS simulator location tools.
library;

import 'dart:io';

import 'package:args/command_runner.dart';

import 'src/commands/replay_command.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<void>(
    'dart run locus:replay',
    'Replay GPX or JSON through OS location simulation.',
  )..addCommand(ReplayCommand(standalone: true));
  try {
    await runner.run(['replay', ...args]);
  } on UsageException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('Error: ${error.message}');
    exitCode = 1;
  } on IOException catch (error) {
    stderr.writeln('Error: $error');
    exitCode = 1;
  }
}
