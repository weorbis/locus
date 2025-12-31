import '../common/json_map.dart';
import 'location.dart';

class LocationQuality {
  final Location location;
  final double accuracyScore;
  final double speedScore;
  final double jitterScore;
  final double overallScore;
  final bool isSpoofSuspected;

  const LocationQuality({
    required this.location,
    required this.accuracyScore,
    required this.speedScore,
    required this.jitterScore,
    required this.overallScore,
    required this.isSpoofSuspected,
  });

  JsonMap toMap() => {
        'location': location.toMap(),
        'accuracyScore': accuracyScore,
        'speedScore': speedScore,
        'jitterScore': jitterScore,
        'overallScore': overallScore,
        'isSpoofSuspected': isSpoofSuspected,
      };
}
