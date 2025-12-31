import '../common/json_map.dart';

class HeadlessEvent {
  final String name;
  final dynamic data;

  const HeadlessEvent({
    required this.name,
    this.data,
  });

  factory HeadlessEvent.fromMap(JsonMap map) {
    return HeadlessEvent(
      name: map['type'] as String? ?? 'unknown',
      data: map['data'],
    );
  }
}
