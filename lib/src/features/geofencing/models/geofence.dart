import 'package:locus/src/shared/models/json_map.dart';
import 'package:locus/src/core/locus_errors.dart';

class Geofence {
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

  /// Creates a Geofence from a map.
  ///
  /// Handles invalid data gracefully by using defaults. Check [isValid]
  /// to verify the geofence configuration is usable.
  ///
  /// For strict validation that throws on invalid data, use [Geofence.fromMapValidated].
  factory Geofence.fromMap(JsonMap map) {
    final identifier = map['identifier'];
    final radius = map['radius'];
    final latitude = map['latitude'];
    final longitude = map['longitude'];
    final extrasData = map['extras'];

    // Parse with graceful fallbacks
    final identifierValue = identifier is String ? identifier : '';
    final radiusValue = radius is num ? radius.toDouble() : 0.0;
    final latValue = latitude is num ? latitude.toDouble() : 0.0;
    final lngValue = longitude is num ? longitude.toDouble() : 0.0;

    return Geofence(
      identifier: identifierValue,
      radius: radiusValue,
      latitude: latValue,
      longitude: lngValue,
      notifyOnEntry: map['notifyOnEntry'] as bool? ?? true,
      notifyOnExit: map['notifyOnExit'] as bool? ?? true,
      notifyOnDwell: map['notifyOnDwell'] as bool? ?? false,
      loiteringDelay: (map['loiteringDelay'] as num?)?.toInt(),
      extras: extrasData is Map ? Map<String, dynamic>.from(extrasData) : null,
    );
  }

  /// Creates a Geofence from a map with strict validation.
  ///
  /// Throws [GeofenceValidationException] if any field is invalid.
  /// Use this when you need to ensure the geofence is valid before use.
  factory Geofence.fromMapValidated(JsonMap map) {
    final identifier = map['identifier'];
    final radius = map['radius'];
    final latitude = map['latitude'];
    final longitude = map['longitude'];
    final extrasData = map['extras'];

    // Validate identifier
    if (identifier is! String || identifier.isEmpty) {
      throw const GeofenceValidationException(
        field: 'identifier',
        reason: 'must be a non-empty string',
      );
    }

    // Validate latitude
    if (latitude is! num) {
      throw const GeofenceValidationException(
        field: 'latitude',
        reason: 'must be a number',
      );
    }
    final latValue = latitude.toDouble();
    if (latValue < -90 || latValue > 90) {
      throw GeofenceValidationException(
        field: 'latitude',
        reason: 'must be between -90 and 90 (got: $latValue)',
      );
    }

    // Validate longitude
    if (longitude is! num) {
      throw const GeofenceValidationException(
        field: 'longitude',
        reason: 'must be a number',
      );
    }
    final lngValue = longitude.toDouble();
    if (lngValue < -180 || lngValue > 180) {
      throw GeofenceValidationException(
        field: 'longitude',
        reason: 'must be between -180 and 180 (got: $lngValue)',
      );
    }

    // Validate radius
    if (radius is! num) {
      throw const GeofenceValidationException(
        field: 'radius',
        reason: 'must be a number',
      );
    }
    final radiusValue = radius.toDouble();
    if (radiusValue <= 0) {
      throw GeofenceValidationException(
        field: 'radius',
        reason: 'must be positive (got: $radiusValue)',
      );
    }
    if (radiusValue > _maxRadius) {
      throw GeofenceValidationException(
        field: 'radius',
        reason: 'must be less than $_maxRadius meters (got: $radiusValue)',
      );
    }

    return Geofence(
      identifier: identifier,
      radius: radiusValue,
      latitude: latValue,
      longitude: lngValue,
      notifyOnEntry: map['notifyOnEntry'] as bool? ?? true,
      notifyOnExit: map['notifyOnExit'] as bool? ?? true,
      notifyOnDwell: map['notifyOnDwell'] as bool? ?? false,
      loiteringDelay: (map['loiteringDelay'] as num?)?.toInt(),
      extras: extrasData is Map ? Map<String, dynamic>.from(extrasData) : null,
    );
  }

  /// Maximum allowed radius in meters (100 km).
  static const double _maxRadius = 100000.0;

  final String identifier;
  final double radius;
  final double latitude;
  final double longitude;
  final bool notifyOnEntry;
  final bool notifyOnExit;
  final bool notifyOnDwell;
  final int? loiteringDelay;
  final JsonMap? extras;

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

  @override
  String toString() =>
      'Geofence($identifier, lat: $latitude, lng: $longitude, radius: ${radius}m)';
}
