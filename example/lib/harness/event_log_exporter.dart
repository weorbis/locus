/// JSON file exporter for the harness event log.
///
/// Writes a self-describing envelope (`exportedAt`, `count`, `events`) so
/// captures can be archived alongside scenario runs and replayed later by a
/// human reviewer or a regression test.
library;

import 'dart:convert';
import 'dart:io';

import 'package:locus_example/harness/recorded_event.dart';

/// Filesystem writer for [RecordedEvent] lists.
///
/// Stateless utility — exposes a single static [writeJson] method. There is
/// no share-sheet integration here on purpose; the file path is enough for
/// the screen layer to surface in a snackbar, and avoiding a third-party
/// share dependency keeps the example app footprint small.
class EventLogExporter {
  const EventLogExporter._();

  /// Indent used for the human-readable JSON output. The full event log can
  /// be hundreds of KB; pretty-printing is cheap and makes diffs readable.
  static const String _indent = '  ';

  /// Writes [events] to a JSON file inside [directory].
  ///
  /// The filename combines [filenamePrefix] with a UTC ISO-8601 timestamp
  /// stripped of `:` characters (illegal on most filesystems). Returns the
  /// written [File].
  ///
  /// Creates [directory] if it does not yet exist. Existing files at the
  /// resolved path are overwritten — same-second exports collide, callers
  /// that need uniqueness should namespace [filenamePrefix].
  static Future<File> writeJson(
    List<RecordedEvent> events, {
    required Directory directory,
    required String filenamePrefix,
  }) async {
    if (filenamePrefix.isEmpty) {
      throw ArgumentError.value(
        filenamePrefix,
        'filenamePrefix',
        'must not be empty',
      );
    }

    // `create(recursive: true)` is a no-op when the directory already
    // exists, so we skip the explicit `exists` probe — the linter rule
    // `avoid_slow_async_io` flags `Directory.exists` for the same reason.
    await directory.create(recursive: true);

    final exportedAt = DateTime.now().toUtc();
    final timestamp = _filesystemSafeTimestamp(exportedAt);
    final path = '${directory.path}/$filenamePrefix-$timestamp.json';
    final file = File(path);

    final envelope = <String, Object?>{
      'exportedAt': exportedAt.toIso8601String(),
      'count': events.length,
      'events': <Map<String, Object?>>[
        for (final event in events) event.toJson(),
      ],
    };

    final encoded = const JsonEncoder.withIndent(_indent).convert(envelope);
    await file.writeAsString(encoded, flush: true);
    return file;
  }

  /// Returns an ISO-8601 UTC timestamp with `:` characters removed so the
  /// resulting string is safe to use as a filename component on macOS,
  /// Windows, and the Android scoped-storage layout.
  static String _filesystemSafeTimestamp(DateTime utc) {
    return utc.toIso8601String().replaceAll(':', '');
  }
}
