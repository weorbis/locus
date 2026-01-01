import 'package:flutter/foundation.dart';

import '../common/json_map.dart';

class Geofence {
  final String identifier;
  final double radius;
  final double latitude;
  final double longitude;
  final bool notifyOnEntry;
  final bool notifyOnExit;
  final bool notifyOnDwell;
  final int? loiteringDelay;
  final JsonMap? extras;

  const Geofence({
    required this.identifier,
    required this.radius,
    required this.latitude,
    required this.longitude,
    this.notifyOnEntry = true,
    this.notifyOnExit = true,
    this.notifyOnDwell = false,
    this.loiteringDelay,
    this.extras,
  });

  /// Returns true if this geofence has valid configuration.
  ///
  /// A geofence is valid if:
  /// - identifier is not empty
  /// - radius is greater than 0
  /// - latitude is between -90 and 90
  /// - longitude is between -180 and 180
  bool get isValid =>
      identifier.isNotEmpty &&
      radius > 0 &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  JsonMap toMap() => {
        'identifier': identifier,
        'radius': radius,
        'latitude': latitude,
        'longitude': longitude,
        'notifyOnEntry': notifyOnEntry,
        'notifyOnExit': notifyOnExit,
        'notifyOnDwell': notifyOnDwell,
        if (loiteringDelay != null) 'loiteringDelay': loiteringDelay,
        if (extras != null) 'extras': extras,
      };

  factory Geofence.fromMap(JsonMap map) {
    final identifier = map['identifier'];
    final radius = map['radius'];
    final latitude = map['latitude'];
    final longitude = map['longitude'];
    final extrasData = map['extras'];

    // Log warning for invalid data
    if (identifier is! String || identifier.isEmpty) {
      debugPrint('[Geofence] Warning: Invalid or missing identifier');
    }
    if (radius is! num || radius <= 0) {
      debugPrint('[Geofence] Warning: Invalid or missing radius');
    }
    if (latitude is! num) {
      debugPrint('[Geofence] Warning: Invalid or missing latitude');
    }
    if (longitude is! num) {
      debugPrint('[Geofence] Warning: Invalid or missing longitude');
    }

    return Geofence(
      identifier: identifier is String ? identifier : '',
      radius: radius is num ? radius.toDouble() : 0.0,
      latitude: latitude is num ? latitude.toDouble() : 0.0,
      longitude: longitude is num ? longitude.toDouble() : 0.0,
      notifyOnEntry: map['notifyOnEntry'] as bool? ?? true,
      notifyOnExit: map['notifyOnExit'] as bool? ?? true,
      notifyOnDwell: map['notifyOnDwell'] as bool? ?? false,
      loiteringDelay: (map['loiteringDelay'] as num?)?.toInt(),
      extras: extrasData is Map ? Map<String, dynamic>.from(extrasData) : null,
    );
  }

  @override
  String toString() =>
      'Geofence($identifier, lat: $latitude, lng: $longitude, radius: ${radius}m)';
}
