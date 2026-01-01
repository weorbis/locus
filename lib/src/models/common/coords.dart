import 'json_map.dart';

/// Exception thrown when coordinate data is invalid.
class InvalidCoordsException implements Exception {
  final String message;
  const InvalidCoordsException(this.message);

  @override
  String toString() => 'InvalidCoordsException: $message';
}

class Coords {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double? speed;
  final double? heading;
  final double? altitude;

  const Coords({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.speed,
    this.heading,
    this.altitude,
  });

  /// Whether these coordinates are within valid Earth ranges.
  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  /// Whether these coordinates are at the null island (0,0).
  /// This is often a sign of missing/invalid data.
  bool get isNullIsland => latitude == 0.0 && longitude == 0.0;

  /// Validates that coordinates are within valid ranges.
  /// Throws [InvalidCoordsException] if invalid.
  void validateRange() {
    if (latitude < -90 || latitude > 90) {
      throw InvalidCoordsException(
          'Latitude must be between -90 and 90, got: $latitude');
    }
    if (longitude < -180 || longitude > 180) {
      throw InvalidCoordsException(
          'Longitude must be between -180 and 180, got: $longitude');
    }
  }

  JsonMap toMap() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        if (speed != null) 'speed': speed,
        if (heading != null) 'heading': heading,
        if (altitude != null) 'altitude': altitude,
      };

  /// Creates Coords from a map.
  ///
  /// Throws [InvalidCoordsException] if latitude or longitude are missing
  /// and [strict] is true (default). If [strict] is false, defaults to 0.0.
  factory Coords.fromMap(JsonMap map, {bool strict = true}) {
    final lat = map['latitude'];
    final lng = map['longitude'];

    if (strict && (lat == null || lng == null)) {
      throw InvalidCoordsException(
          'Missing required coordinates: latitude=${lat != null}, longitude=${lng != null}');
    }

    final latitude = (lat as num?)?.toDouble() ?? 0.0;
    final longitude = (lng as num?)?.toDouble() ?? 0.0;

    // Validate ranges
    if (latitude < -90 || latitude > 90) {
      throw InvalidCoordsException(
          'Latitude must be between -90 and 90, got: $latitude');
    }
    if (longitude < -180 || longitude > 180) {
      throw InvalidCoordsException(
          'Longitude must be between -180 and 180, got: $longitude');
    }

    return Coords(
      latitude: latitude,
      longitude: longitude,
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0.0,
      speed: (map['speed'] as num?)?.toDouble(),
      heading: (map['heading'] as num?)?.toDouble(),
      altitude: (map['altitude'] as num?)?.toDouble(),
    );
  }

  /// Creates Coords from a map, returning null if data is invalid.
  /// Use this when you want to gracefully handle invalid data.
  static Coords? tryFromMap(JsonMap map) {
    try {
      return Coords.fromMap(map);
    } on InvalidCoordsException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Coords &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          accuracy == other.accuracy &&
          speed == other.speed &&
          heading == other.heading &&
          altitude == other.altitude;

  @override
  int get hashCode => Object.hash(
        latitude,
        longitude,
        accuracy,
        speed,
        heading,
        altitude,
      );

  @override
  String toString() =>
      'Coords(lat: $latitude, lng: $longitude, acc: $accuracy)';
}
