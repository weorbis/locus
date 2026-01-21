import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:locus/src/shared/models/json_map.dart';

/// A geographic coordinate point (vertex) for polygon geofences.
class GeoPoint {
  const GeoPoint({
    required this.latitude,
    required this.longitude,
  });

  factory GeoPoint.fromMap(JsonMap map) {
    return GeoPoint(
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Latitude in degrees (-90 to 90).
  final double latitude;

  /// Longitude in degrees (-180 to 180).
  final double longitude;

  /// Returns true if this point has valid coordinates.
  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  JsonMap toMap() => {
        'latitude': latitude,
        'longitude': longitude,
      };

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoPoint &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}

/// A geofence defined by a polygon (list of vertices).
///
/// Polygon geofences allow defining irregular shapes for geofencing,
/// such as building outlines, parking lots, or delivery zones.
///
/// The polygon must have at least 3 vertices to form a valid shape.
/// Vertices should be defined in order (clockwise or counter-clockwise).
/// The polygon is automatically closed (last vertex connects to first).
class PolygonGeofence {
  PolygonGeofence({
    required this.identifier,
    required this.vertices,
    this.notifyOnEntry = true,
    this.notifyOnExit = true,
    this.notifyOnDwell = false,
    this.loiteringDelay,
    this.extras,
  });

  factory PolygonGeofence.fromMap(JsonMap map) {
    final identifier = map['identifier'];
    final verticesRaw = map['vertices'];

    if (identifier is! String || identifier.isEmpty) {
      debugPrint('[PolygonGeofence] Warning: Invalid or missing identifier');
    }
    if (verticesRaw is! List || verticesRaw.length < 3) {
      debugPrint(
          '[PolygonGeofence] Warning: Invalid vertices (need at least 3)');
    }

    final vertices = <GeoPoint>[];
    if (verticesRaw is List) {
      for (final v in verticesRaw) {
        if (v is Map) {
          vertices.add(GeoPoint.fromMap(Map<String, dynamic>.from(v)));
        }
      }
    }

    final extrasData = map['extras'];

    return PolygonGeofence(
      identifier: identifier is String ? identifier : '',
      vertices: vertices,
      notifyOnEntry: map['notifyOnEntry'] as bool? ?? true,
      notifyOnExit: map['notifyOnExit'] as bool? ?? true,
      notifyOnDwell: map['notifyOnDwell'] as bool? ?? false,
      loiteringDelay: (map['loiteringDelay'] as num?)?.toInt(),
      extras: extrasData is Map ? Map<String, dynamic>.from(extrasData) : null,
    );
  }

  /// Unique identifier for this geofence.
  final String identifier;

  /// List of vertices defining the polygon boundary.
  /// Must have at least 3 points.
  final List<GeoPoint> vertices;

  /// Whether to trigger on entry events.
  final bool notifyOnEntry;

  /// Whether to trigger on exit events.
  final bool notifyOnExit;

  /// Whether to trigger on dwell events (staying inside).
  final bool notifyOnDwell;

  /// Minimum time (ms) to trigger dwell event.
  final int? loiteringDelay;

  /// Additional metadata for this geofence.
  final JsonMap? extras;

  /// Returns true if this polygon geofence has valid configuration.
  ///
  /// A polygon geofence is valid if:
  /// - identifier is not empty
  /// - has at least 3 vertices
  /// - all vertices have valid coordinates
  bool get isValid =>
      identifier.isNotEmpty &&
      vertices.length >= 3 &&
      vertices.every((v) => v.isValid);

  /// Returns the centroid (geometric center) of the polygon.
  GeoPoint get centroid {
    if (vertices.isEmpty) {
      return const GeoPoint(latitude: 0, longitude: 0);
    }

    double latSum = 0;
    double lngSum = 0;

    for (final vertex in vertices) {
      latSum += vertex.latitude;
      lngSum += vertex.longitude;
    }

    return GeoPoint(
      latitude: latSum / vertices.length,
      longitude: lngSum / vertices.length,
    );
  }

  /// Returns the bounding box of the polygon as `minLat, minLng, maxLat, maxLng`.
  List<double> get boundingBox {
    if (vertices.isEmpty) {
      return [0, 0, 0, 0];
    }

    double minLat = vertices.first.latitude;
    double maxLat = vertices.first.latitude;
    double minLng = vertices.first.longitude;
    double maxLng = vertices.first.longitude;

    for (final vertex in vertices) {
      if (vertex.latitude < minLat) minLat = vertex.latitude;
      if (vertex.latitude > maxLat) maxLat = vertex.latitude;
      if (vertex.longitude < minLng) minLng = vertex.longitude;
      if (vertex.longitude > maxLng) maxLng = vertex.longitude;
    }

    return [minLat, minLng, maxLat, maxLng];
  }

  double? _areaSquareMeters;

  /// Calculates the approximate area of the polygon in square meters.
  ///
  /// Uses the Shoelace formula with geodesic corrections.
  /// The result is cached after the first calculation.
  double get areaSquareMeters {
    if (_areaSquareMeters != null) return _areaSquareMeters!;
    if (vertices.length < 3) return 0;

    // Earth's radius in meters
    const earthRadius = 6371000.0;

    // Convert to radians and use spherical excess formula
    double area = 0;
    final n = vertices.length;

    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      final lat1 = vertices[i].latitude * math.pi / 180;
      final lng1 = vertices[i].longitude * math.pi / 180;
      final lat2 = vertices[j].latitude * math.pi / 180;
      final lng2 = vertices[j].longitude * math.pi / 180;

      area += (lng2 - lng1) * (2 + math.sin(lat1) + math.sin(lat2));
    }

    area = (area * earthRadius * earthRadius / 2).abs();
    _areaSquareMeters = area;
    return area;
  }

  /// Returns true if the given point is inside this polygon.
  ///
  /// Uses the ray casting algorithm (point-in-polygon test).
  /// A ray is cast from the point to infinity and the number of
  /// intersections with polygon edges is counted. Odd = inside.
  bool containsPoint(double latitude, double longitude) {
    if (vertices.length < 3) return false;

    // Quick bounding box check first
    final bbox = boundingBox;
    if (latitude < bbox[0] ||
        latitude > bbox[2] ||
        longitude < bbox[1] ||
        longitude > bbox[3]) {
      return false;
    }

    // Ray casting algorithm
    bool inside = false;
    final n = vertices.length;

    for (int i = 0, j = n - 1; i < n; j = i++) {
      final yi = vertices[i].latitude;
      final xi = vertices[i].longitude;
      final yj = vertices[j].latitude;
      final xj = vertices[j].longitude;

      if (((yi > latitude) != (yj > latitude)) &&
          (longitude < (xj - xi) * (latitude - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
    }

    return inside;
  }

  /// Returns true if the given GeoPoint is inside this polygon.
  bool containsGeoPoint(GeoPoint point) {
    return containsPoint(point.latitude, point.longitude);
  }

  /// Returns the approximate perimeter of the polygon in meters.
  double get perimeterMeters {
    if (vertices.length < 2) return 0;

    double perimeter = 0;
    final n = vertices.length;

    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      perimeter += _haversineDistance(
        vertices[i].latitude,
        vertices[i].longitude,
        vertices[j].latitude,
        vertices[j].longitude,
      );
    }

    return perimeter;
  }

  /// Calculates distance between two points using Haversine formula.
  static double _haversineDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371000.0; // meters

    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  JsonMap toMap() => {
        'identifier': identifier,
        'vertices': vertices.map((v) => v.toMap()).toList(),
        'notifyOnEntry': notifyOnEntry,
        'notifyOnExit': notifyOnExit,
        'notifyOnDwell': notifyOnDwell,
        if (loiteringDelay != null) 'loiteringDelay': loiteringDelay,
        if (extras != null) 'extras': extras,
      };

  /// Creates a copy with the given fields replaced.
  PolygonGeofence copyWith({
    String? identifier,
    List<GeoPoint>? vertices,
    bool? notifyOnEntry,
    bool? notifyOnExit,
    bool? notifyOnDwell,
    int? loiteringDelay,
    JsonMap? extras,
  }) {
    return PolygonGeofence(
      identifier: identifier ?? this.identifier,
      vertices: vertices ?? this.vertices,
      notifyOnEntry: notifyOnEntry ?? this.notifyOnEntry,
      notifyOnExit: notifyOnExit ?? this.notifyOnExit,
      notifyOnDwell: notifyOnDwell ?? this.notifyOnDwell,
      loiteringDelay: loiteringDelay ?? this.loiteringDelay,
      extras: extras ?? this.extras,
    );
  }

  @override
  String toString() =>
      'PolygonGeofence($identifier, ${vertices.length} vertices)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PolygonGeofence &&
          runtimeType == other.runtimeType &&
          identifier == other.identifier;

  @override
  int get hashCode => identifier.hashCode;
}

/// Event emitted when polygon geofence state changes.
class PolygonGeofenceEvent {
  const PolygonGeofenceEvent({
    required this.geofence,
    required this.type,
    required this.timestamp,
    this.triggerLocation,
  });

  factory PolygonGeofenceEvent.fromMap(JsonMap map) {
    return PolygonGeofenceEvent(
      geofence: PolygonGeofence.fromMap(
          Map<String, dynamic>.from(map['geofence'] as Map)),
      type: PolygonGeofenceEventType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => PolygonGeofenceEventType.enter,
      ),
      timestamp: DateTime.parse(map['timestamp'] as String),
      triggerLocation: map['triggerLocation'] != null
          ? GeoPoint.fromMap(
              Map<String, dynamic>.from(map['triggerLocation'] as Map))
          : null,
    );
  }

  /// The polygon geofence that triggered this event.
  final PolygonGeofence geofence;

  /// The type of event (enter, exit, dwell).
  final PolygonGeofenceEventType type;

  /// Timestamp when the event occurred.
  final DateTime timestamp;

  /// The location that triggered this event, if available.
  final GeoPoint? triggerLocation;

  JsonMap toMap() => {
        'geofence': geofence.toMap(),
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        if (triggerLocation != null)
          'triggerLocation': triggerLocation!.toMap(),
      };
}

/// Types of polygon geofence events.
enum PolygonGeofenceEventType {
  /// Device entered the polygon.
  enter,

  /// Device exited the polygon.
  exit,

  /// Device is dwelling inside the polygon.
  dwell,
}
