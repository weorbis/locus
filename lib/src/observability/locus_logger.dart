import 'package:logging/logging.dart';

/// Returns a [Logger] inside the `locus.*` namespace.
///
/// Locus emits all of its diagnostics through `package:logging` so embedders
/// can attach a single root listener and forward records into their own
/// telemetry pipeline (Sentry breadcrumbs, structured HTTP sinks, etc.).
///
/// Example:
///
/// ```dart
/// final _log = locusLogger('sync');
/// _log.info('starting sync');
/// _log.eventWarning('sync_retry_scheduled', {'attempt': 3, 'delay_ms': 1500});
/// ```
Logger locusLogger(String area) {
  if (area.isEmpty) {
    throw ArgumentError('locusLogger area must not be empty');
  }
  return Logger('locus.$area');
}

/// A structured event payload that travels with a [LogRecord].
///
/// `package:logging` stringifies the object into [LogRecord.message] and also
/// stores the original instance on [LogRecord.object]. Embedder-side adapters
/// can recover the typed key/value pairs from `record.object` instead of
/// re-parsing the rendered string.
final class LocusEvent {
  const LocusEvent(this.name, [this.attributes = const {}]);

  /// Short, low-cardinality event name (e.g. `sync_succeeded`,
  /// `points_evicted`). Used for grouping and dashboard search.
  final String name;

  /// Free-form key/value attributes. Keys MUST be `snake_case`.
  /// Values must be primitives (`String`, `num`, `bool`, `DateTime`, `null`).
  final Map<String, Object?> attributes;

  @override
  String toString() {
    if (attributes.isEmpty) return name;
    final pairs = attributes.entries
        .map((e) => '${e.key}=${_format(e.value)}')
        .join(' ');
    return '$name $pairs';
  }

  static String _format(Object? value) {
    if (value == null) return 'null';
    if (value is DateTime) return value.toUtc().toIso8601String();
    return value.toString();
  }
}

/// Convenience shortcuts for emitting a [LocusEvent] at the typical levels.
///
/// The plain [Logger.info]/`warning`/`severe` calls remain for unstructured
/// human messages; use these `event*` helpers when you want a stable event
/// name + key/value attributes that downstream systems can index.
extension LocusLoggerEvents on Logger {
  void eventFine(String name, [Map<String, Object?> attributes = const {}]) =>
      log(Level.FINE, LocusEvent(name, attributes));

  void eventInfo(String name, [Map<String, Object?> attributes = const {}]) =>
      log(Level.INFO, LocusEvent(name, attributes));

  void eventWarning(
    String name, [
    Map<String, Object?> attributes = const {},
    Object? error,
    StackTrace? stackTrace,
  ]) =>
      log(Level.WARNING, LocusEvent(name, attributes), error, stackTrace);

  void eventSevere(
    String name, [
    Map<String, Object?> attributes = const {},
    Object? error,
    StackTrace? stackTrace,
  ]) =>
      log(Level.SEVERE, LocusEvent(name, attributes), error, stackTrace);
}
