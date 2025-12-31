import 'enums.dart';
import 'json_map.dart';

class Activity {
  final ActivityType type;
  final int confidence;

  const Activity({
    required this.type,
    required this.confidence,
  });

  JsonMap toMap() => {
        'type': type.name,
        'confidence': confidence,
      };

  factory Activity.fromMap(JsonMap map) {
    return Activity(
      type: ActivityType.values.firstWhere(
        (value) => value.name == map['type'],
        orElse: () => ActivityType.unknown,
      ),
      confidence: (map['confidence'] as num?)?.toInt() ?? 0,
    );
  }
}
