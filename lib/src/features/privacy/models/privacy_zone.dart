import 'dart:math' as math;

import 'package:locus/src/shared/models/json_map.dart';
import 'package:locus/src/features/location/models/location.dart';

/// Action to take when a location is within a privacy zone.
enum PrivacyZoneAction {
  /// Obfuscate coordinates by offsetting or masking them.
  /// The location will still be stored/synced but with modified coordinates.
  obfuscate,

  /// Exclude the location entirely.
  /// The location will not be stored, synced, or appear in history.
  exclude,
}

/// Defines a circular privacy zone where location data is protected.
///
/// Privacy zones allow apps to define areas where location data should be
/// obfuscated or excluded entirely, supporting privacy compliance requirements.
///
/// Example:
/// ```dart
/// final homeZone = PrivacyZone(
///   identifier: 'home',
///   latitude: 37.7749,
///   longitude: -122.4194,
///   radius: 100.0,
///   action: PrivacyZoneAction.obfuscate,
///   obfuscationRadius: 500.0,
/// );
/// ```
class PrivacyZone {
  /// Unique identifier for this privacy zone.
  final String identifier;

  /// Center latitude of the zone.
  final double latitude;

  /// Center longitude of the zone.
  final double longitude;

  /// Radius in meters defining the zone boundary.
  final double radius;

  /// Action to take when location is within this zone.
  final PrivacyZoneAction action;

  /// For obfuscate action: radius within which to randomly offset coordinates.
  /// Defaults to 500 meters if not specified.
  final double obfuscationRadius;

  /// Optional label for display purposes.
  final String? label;

  /// Whether this zone is currently active.
  final bool enabled;

  /// Optional metadata for this zone.
  final JsonMap? extras;

  /// When this zone was created.
  final DateTime createdAt;

  /// When this zone was last updated.
  final DateTime? updatedAt;

  const PrivacyZone({
    required this.identifier,
    required this.latitude,
    required this.longitude,
    required this.radius,
    this.action = PrivacyZoneAction.obfuscate,
    this.obfuscationRadius = 500.0,
    this.label,
    this.enabled = true,
    this.extras,
    required this.createdAt,
    this.updatedAt,
  });

  /// Creates a privacy zone with current timestamp.
  factory PrivacyZone.create({
    required String identifier,
    required double latitude,
    required double longitude,
    required double radius,
    PrivacyZoneAction action = PrivacyZoneAction.obfuscate,
    double obfuscationRadius = 500.0,
    String? label,
    bool enabled = true,
    JsonMap? extras,
  }) {
    return PrivacyZone(
      identifier: identifier,
      latitude: latitude,
      longitude: longitude,
      radius: radius,
      action: action,
      obfuscationRadius: obfuscationRadius,
      label: label,
      enabled: enabled,
      extras: extras,
      createdAt: DateTime.now(),
    );
  }

  /// Whether this zone configuration is valid.
  bool get isValid =>
      identifier.isNotEmpty &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      radius > 0 &&
      obfuscationRadius > 0;

  /// Checks if a location point is within this privacy zone.
  bool containsLocation(double lat, double lng) {
    final distance = _haversineDistance(latitude, longitude, lat, lng);
    return distance <= radius;
  }

  /// Checks if a [Location] is within this privacy zone.
  bool containsLocationObject(Location location) {
    return containsLocation(
      location.coords.latitude,
      location.coords.longitude,
    );
  }

  /// Calculates the Haversine distance between two points in meters.
  static double _haversineDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371000.0; // meters

    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  /// Creates a copy with modified values.
  PrivacyZone copyWith({
    String? identifier,
    double? latitude,
    double? longitude,
    double? radius,
    PrivacyZoneAction? action,
    double? obfuscationRadius,
    String? label,
    bool? enabled,
    JsonMap? extras,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PrivacyZone(
      identifier: identifier ?? this.identifier,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radius: radius ?? this.radius,
      action: action ?? this.action,
      obfuscationRadius: obfuscationRadius ?? this.obfuscationRadius,
      label: label ?? this.label,
      enabled: enabled ?? this.enabled,
      extras: extras ?? this.extras,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  JsonMap toMap() => {
        'identifier': identifier,
        'latitude': latitude,
        'longitude': longitude,
        'radius': radius,
        'action': action.name,
        'obfuscationRadius': obfuscationRadius,
        if (label != null) 'label': label,
        'enabled': enabled,
        if (extras != null) 'extras': extras,
        'createdAt': createdAt.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      };

  factory PrivacyZone.fromMap(JsonMap map) {
    return PrivacyZone(
      identifier: map['identifier'] as String? ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      radius: (map['radius'] as num?)?.toDouble() ?? 0.0,
      action: PrivacyZoneAction.values.firstWhere(
        (a) => a.name == map['action'],
        orElse: () => PrivacyZoneAction.obfuscate,
      ),
      obfuscationRadius:
          (map['obfuscationRadius'] as num?)?.toDouble() ?? 500.0,
      label: map['label'] as String?,
      enabled: map['enabled'] as bool? ?? true,
      extras: map['extras'] is Map
          ? Map<String, dynamic>.from(map['extras'] as Map)
          : null,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : null,
    );
  }

  @override
  String toString() =>
      'PrivacyZone($identifier, center: ($latitude, $longitude), '
      'radius: ${radius}m, action: ${action.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrivacyZone &&
          runtimeType == other.runtimeType &&
          identifier == other.identifier;

  @override
  int get hashCode => identifier.hashCode;
}

/// Result of applying privacy zone rules to a location.
class PrivacyZoneResult {
  /// The original location (before any modification).
  final Location originalLocation;

  /// The processed location (may be obfuscated or null if excluded).
  final Location? processedLocation;

  /// The zones that matched this location.
  final List<PrivacyZone> matchedZones;

  /// Whether the location was excluded entirely.
  final bool wasExcluded;

  /// Whether the location was obfuscated.
  final bool wasObfuscated;

  const PrivacyZoneResult({
    required this.originalLocation,
    this.processedLocation,
    this.matchedZones = const [],
    this.wasExcluded = false,
    this.wasObfuscated = false,
  });

  /// Whether the location was affected by any privacy zone.
  bool get wasAffected => wasExcluded || wasObfuscated;

  /// Whether the location can be used (not excluded).
  bool get isUsable => !wasExcluded && processedLocation != null;

  JsonMap toMap() => {
        'originalLocation': originalLocation.toMap(),
        if (processedLocation != null)
          'processedLocation': processedLocation!.toMap(),
        'matchedZones': matchedZones.map((z) => z.toMap()).toList(),
        'wasExcluded': wasExcluded,
        'wasObfuscated': wasObfuscated,
      };
}
