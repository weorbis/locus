import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:args/command_runner.dart';

import '../replay/route.dart';

const _earthRadiusMeters = 6371008.8;
const _degreesToRadians = math.pi / 180;
const _commandTimeout = Duration(seconds: 30);
const _interruptExitCode = 130;
const _maxDurationMicros = 9223372036854775807;

class ReplayCommand extends Command<void> {
  ReplayCommand({this.standalone = false}) {
    argParser
      ..addOption(
        'platform',
        allowed: ['android', 'ios'],
        help: 'Target OS (required).',
      )
      ..addOption('device', help: 'Android emulator serial or booted iOS UDID.')
      ..addOption(
        'interval',
        help: 'Fixed seconds between points; overrides timestamps.',
      )
      ..addOption(
        'speed-multiplier',
        defaultsTo: '1',
        help: 'Divide recorded time gaps by this positive number.',
      )
      ..addFlag('loop', negatable: false, help: 'Repeat until Ctrl+C.')
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print commands and delays once, without tools or waiting.',
      );
  }

  final bool standalone;

  @override
  final name = 'replay';

  @override
  final description = 'Replay GPX or JSON through OS location simulation.';

  @override
  String get invocation =>
      '${runner?.executableName}${standalone ? '' : ' replay'} [options] <route.gpx|route.json>';

  @override
  String get usage => standalone
      ? '$description\n\nUsage: $invocation\n${argParser.usage}'
      : super.usage;

  @override
  Future<void> run() async {
    final results = argResults;
    if (results == null) usageException('Missing arguments.');
    final platform = results.option('platform');
    if (platform == null || results.rest.length != 1) {
      usageException('Provide --platform and exactly one route file.');
    }
    final intervalText = results.option('interval');
    final interval = intervalText == null
        ? null
        : _positive(intervalText, 'interval');
    final multiplier = _positive(
      results.option('speed-multiplier')!,
      'speed-multiplier',
    );
    if (interval != null && results.wasParsed('speed-multiplier')) {
      usageException(
        '--interval and --speed-multiplier are mutually exclusive.',
      );
    }
    final repeatGap = _duration(
      interval ?? defaultIntervalSeconds / multiplier,
    );
    final points = parseRoute(await File(results.rest.single).readAsString());
    final gaps = <Duration>[];
    var fallbackGaps = 0;
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1].time;
      final current = points[index].time;
      double seconds;
      if (interval != null) {
        seconds = interval;
      } else if (previous != null && current != null) {
        seconds =
            current.difference(previous).inMicroseconds /
            Duration.microsecondsPerSecond /
            multiplier;
        if (seconds < 0) {
          throw const FormatException(
            'Route timestamps must not go backwards. Use --interval to override.',
          );
        }
      } else {
        seconds = defaultIntervalSeconds / multiplier;
        fallbackGaps++;
      }
      gaps.add(_duration(seconds));
    }
    final dryRun = results.flag('dry-run');
    final session = _ReplaySession(dryRun: dryRun);
    final interrupt = ProcessSignal.sigint.watch().listen(
      (_) => session.stop(),
    );
    final terminate = Platform.isWindows
        ? null
        : ProcessSignal.sigterm.watch().listen((_) => session.stop());
    String? device;
    var iosStarted = false;
    try {
      device = dryRun
          ? results.option('device') ?? '<device>'
          : await _findDevice(session, platform, results.option('device'));
      if (session.stopped) return;
      stdout.writeln(
        'Replaying ${points.length} points on $platform ($device).',
      );
      if (fallbackGaps > 0) {
        stdout.writeln(
          '$fallbackGaps gaps lack timestamps; using ${defaultIntervalSeconds / multiplier}s.',
        );
      }
      if (platform == 'ios' && points.any((point) => point.altitude != null)) {
        stdout.writeln(
          'iOS simctl waypoint routes do not accept altitude; elevations are ignored.',
        );
      }
      if (dryRun && results.flag('loop')) {
        stdout.writeln(
          'Dry run shows one loop; live replay repeats it until Ctrl+C.',
        );
      }
      do {
        if (platform == 'android') {
          for (
            var index = 0;
            index < points.length && !session.stopped;
            index++
          ) {
            if (index > 0) await session.wait(gaps[index - 1]);
            if (session.stopped) break;
            final point = points[index];
            await session.command('adb', [
              '-s',
              device,
              'emu',
              'geo',
              'fix',
              '${point.longitude}',
              '${point.latitude}',
              if (point.altitude != null) '${point.altitude}',
            ]);
          }
        } else {
          iosStarted = true;
          await session.command('xcrun', [
            'simctl',
            'location',
            device,
            'set',
            points.first.pair,
          ]);
          for (
            var index = 1;
            index < points.length && !session.stopped;
            index++
          ) {
            final gap = gaps[index - 1];
            final distance = _distance(points[index - 1], points[index]);
            if (gap > Duration.zero && distance > 0) {
              final seconds =
                  gap.inMicroseconds / Duration.microsecondsPerSecond;
              await session.command('xcrun', [
                'simctl',
                'location',
                device,
                'start',
                '--speed=${distance / seconds}',
                '--interval=${math.min(defaultIntervalSeconds, seconds)}',
                points[index - 1].pair,
                points[index].pair,
              ]);
            }
            await session.wait(gap);
            if (!session.stopped) {
              await session.command('xcrun', [
                'simctl',
                'location',
                device,
                'set',
                points[index].pair,
              ]);
            }
          }
        }
        if ((platform == 'ios' || results.flag('loop')) && !session.stopped) {
          await session.wait(repeatGap);
        }
      } while (results.flag('loop') && !dryRun && !session.stopped);
    } finally {
      try {
        if (iosStarted && device != null) {
          await session.command('xcrun', [
            'simctl',
            'location',
            device,
            'clear',
          ], cleanup: true);
        }
      } finally {
        await interrupt.cancel();
        await terminate?.cancel();
        if (session.stopped) exitCode = _interruptExitCode;
      }
    }
  }

  double _positive(String text, String name) {
    final value = double.tryParse(text);
    if (value == null ||
        !value.isFinite ||
        value <= 0 ||
        value * Duration.microsecondsPerSecond >= _maxDurationMicros) {
      usageException(
        '--$name must be a finite positive number within the supported duration range.',
      );
    }
    return value;
  }
}

Duration _duration(double seconds) {
  final micros = seconds * Duration.microsecondsPerSecond;
  if (!micros.isFinite || micros >= _maxDurationMicros) {
    throw const FormatException('Replay delay is too large.');
  }
  if (seconds > 0 && micros < 1) {
    throw const FormatException(
      'Replay delays must be at least one microsecond.',
    );
  }
  return Duration(microseconds: micros.round());
}

Future<String> _findDevice(
  _ReplaySession session,
  String platform,
  String? requested,
) async {
  final devices = <String>[];
  if (platform == 'android') {
    final listing = await session.command('adb', ['devices']);
    for (final line in const LineSplitter().convert(listing)) {
      final match = RegExp(r'^(\S+)\s+device(?:\s|$)').firstMatch(line);
      final serial = match?.group(1);
      // Auto-selection only considers local emulators; any ready serial
      // (for example an emulator reached through `adb connect`) can be named.
      if (serial == null) continue;
      if (serial == requested || serial.startsWith('emulator-')) {
        devices.add(serial);
      }
    }
  } else {
    final listing = await session.command('xcrun', [
      'simctl',
      'list',
      'devices',
      'booted',
      '--json',
    ]);
    if (session.stopped) return '';
    final Object? data = jsonDecode(listing);
    if (data is! Map<String, Object?> ||
        data['devices'] is! Map<String, Object?>) {
      throw const FormatException('Unexpected simctl device listing.');
    }
    final runtimes = data['devices'];
    if (runtimes is Map<String, Object?>) {
      for (final runtime in runtimes.entries) {
        if (!runtime.key.contains('.iOS-')) continue;
        final entries = runtime.value;
        if (entries is! List<Object?>) {
          throw const FormatException('Unexpected simctl runtime listing.');
        }
        for (final entry in entries) {
          if (entry is Map<String, Object?> && entry['state'] == 'Booted') {
            final udid = entry['udid'];
            if (udid is String) devices.add(udid);
          }
        }
      }
    }
  }
  if (session.stopped) return '';
  if (requested != null && devices.contains(requested)) return requested;
  if (requested == null && devices.length == 1) return devices.single;
  throw FormatException(
    requested == null
        ? 'Expected one ready $platform emulator/simulator; found ${devices.length}. '
              'Boot a device or use --device. Available: ${devices.join(', ')}'
        : 'Device $requested is not a ready $platform emulator/simulator. Available: ${devices.join(', ')}',
  );
}

double _distance(RoutePoint a, RoutePoint b) {
  final lat = (b.latitude - a.latitude) * _degreesToRadians;
  final lon = (b.longitude - a.longitude) * _degreesToRadians;
  final haversine =
      math.pow(math.sin(lat / 2), 2) +
      math.cos(a.latitude * _degreesToRadians) *
          math.cos(b.latitude * _degreesToRadians) *
          math.pow(math.sin(lon / 2), 2);
  return 2 * _earthRadiusMeters * math.asin(math.sqrt(haversine.clamp(0, 1)));
}

class _ReplaySession {
  _ReplaySession({required this.dryRun});

  final bool dryRun;
  final _cancelled = Completer<void>();
  Process? _active;
  bool get stopped => _cancelled.isCompleted;

  void stop() {
    if (!stopped) _cancelled.complete();
    _active?.kill();
  }

  Future<void> wait(Duration duration) async {
    if (dryRun) {
      stdout.writeln(
        'wait ${duration.inMicroseconds / Duration.microsecondsPerSecond}s',
      );
      return;
    }
    if (stopped || duration == Duration.zero) return;
    final done = Completer<void>();
    final timer = Timer(duration, done.complete);
    try {
      await Future.any([done.future, _cancelled.future]);
    } finally {
      timer.cancel();
    }
  }

  Future<String> command(
    String executable,
    List<String> args, {
    bool cleanup = false,
  }) async {
    if (stopped && !cleanup) return '';
    if (dryRun) {
      stdout.writeln([executable, ...args].map(_quote).join(' '));
      return '';
    }
    final process = await Process.start(executable, args);
    _active = cleanup ? null : process;
    if (stopped && !cleanup) process.kill();
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    var timedOut = false;
    final timer = Timer(_commandTimeout, () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
    });
    try {
      final status = await process.exitCode;
      final text = await output;
      final error = await errors;
      if (stopped && !cleanup) return '';
      if (timedOut || status != 0 || text.trimLeft().startsWith('KO:')) {
        throw ProcessException(
          executable,
          args,
          '${timedOut ? 'Command timed out after ${_commandTimeout.inSeconds}s' : 'Command failed ($status)'}: ${error.trim()} ${text.trim()}',
          status,
        );
      }
      if (error.trim().isNotEmpty) stderr.writeln(error.trim());
      return text;
    } finally {
      timer.cancel();
      _active = null;
    }
  }
}

String _quote(String value) =>
    RegExp(r'^[a-zA-Z0-9_.,:/=+\-]+$').hasMatch(value)
    ? value
    : "'${value.replaceAll("'", "'\\''")}'";
