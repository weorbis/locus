import 'package:locus/src/shared/models/enums.dart';
import 'package:locus/src/features/tracking/models/tracking_profile.dart';

enum TrackingProfileRuleType {
  activity,
  geofence,
  speedAbove,
  speedBelow,
}

class TrackingProfileRule {
  final TrackingProfile profile;
  final TrackingProfileRuleType type;
  final ActivityType? activity;
  final GeofenceAction? geofenceAction;
  final String? geofenceIdentifier;
  final double? speedKph;
  final int cooldownSeconds;

  const TrackingProfileRule({
    required this.profile,
    required this.type,
    this.activity,
    this.geofenceAction,
    this.geofenceIdentifier,
    this.speedKph,
    this.cooldownSeconds = 30,
  });
}
