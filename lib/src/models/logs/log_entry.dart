import '../common/json_map.dart';

class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;
  final String? tag;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.tag,
  });

  JsonMap toMap() => {
        'timestamp': timestamp.millisecondsSinceEpoch,
        'level': level,
        'message': message,
        if (tag != null) 'tag': tag,
      };

  factory LogEntry.fromMap(JsonMap map) {
    final rawTimestamp = map['timestamp'];
    final parsedMs = _parseTimestampMs(rawTimestamp);

    return LogEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch(parsedMs),
      level: map['level'] as String? ?? 'info',
      message: map['message'] as String? ?? '',
      tag: map['tag'] as String?,
    );
  }

  static int _parseTimestampMs(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw < 1000000000000 ? (raw * 1000).round() : raw.toInt();
    }
    if (raw is String) {
      final value = double.tryParse(raw);
      if (value != null) {
        return value < 1000000000000 ? (value * 1000).round() : value.toInt();
      }
    }
    return DateTime.now().millisecondsSinceEpoch;
  }
}
