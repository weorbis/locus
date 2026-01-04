import 'package:locus/src/shared/models/json_map.dart';

class Battery {
  final double level;
  final bool isCharging;

  const Battery({
    required this.level,
    required this.isCharging,
  });

  JsonMap toMap() => {
        'level': level,
        'is_charging': isCharging,
      };

  factory Battery.fromMap(JsonMap map) {
    return Battery(
      level: (map['level'] as num?)?.toDouble() ?? 0.0,
      isCharging: map['is_charging'] as bool? ?? false,
    );
  }
}
