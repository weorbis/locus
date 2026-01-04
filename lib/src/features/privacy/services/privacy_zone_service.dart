import 'dart:async';
import 'dart:math' as math;

import 'package:locus/src/shared/models/coords.dart';
import 'package:locus/src/shared/models/json_map.dart';
import 'package:locus/src/features/location/models/location.dart';
import 'package:locus/src/features/privacy/models/privacy_zone.dart';

/// Service for managing privacy zones and applying location obfuscation.
///
/// Privacy zones allow apps to define areas where location data should be
/// protected. This supports GDPR and other privacy compliance requirements.
///
/// Example:
/// ```dart
/// final service = PrivacyZoneService();
///
/// // Add a privacy zone around home
/// await service.addZone(PrivacyZone.create(
///   identifier: 'home',
///   latitude: 37.7749,
///   longitude: -122.4194,
///   radius: 100.0,
///   action: PrivacyZoneAction.obfuscate,
/// ));
///
/// // Process location through privacy filter
/// final result = service.processLocation(myLocation);
/// if (result.isUsable) {
///   // Use result.processedLocation
/// }
/// ```
class PrivacyZoneService {
  /// In-memory storage of privacy zones.
  final Map<String, PrivacyZone> _zones = {};

  /// Stream controller for zone changes.
  final _zoneChangesController =
      StreamController<PrivacyZoneEvent>.broadcast();

  /// Random number generator for obfuscation.
  final math.Random _random;

  /// Optional persistence callback - called when zones change.
  final Future<void> Function(List<PrivacyZone>)? _onPersist;

  /// Creates a new PrivacyZoneService.
  ///
  /// [onPersist] - Optional callback for persisting zones to storage.
  /// [seed] - Optional random seed for deterministic testing.
  PrivacyZoneService({
    Future<void> Function(List<PrivacyZone>)? onPersist,
    int? seed,
  })  : _onPersist = onPersist,
        _random = seed != null ? math.Random(seed) : math.Random();

  /// Stream of privacy zone change events.
  Stream<PrivacyZoneEvent> get zoneChanges => _zoneChangesController.stream;

  /// All registered privacy zones.
  List<PrivacyZone> get zones => _zones.values.toList();

  /// All enabled privacy zones.
  List<PrivacyZone> get enabledZones =>
      _zones.values.where((z) => z.enabled).toList();

  /// Number of registered zones.
  int get zoneCount => _zones.length;

  /// Adds a privacy zone.
  Future<void> addZone(PrivacyZone zone) async {
    if (!zone.isValid) {
      throw ArgumentError('Invalid privacy zone configuration');
    }

    final isNew = !_zones.containsKey(zone.identifier);
    _zones[zone.identifier] = zone;

    _zoneChangesController.add(PrivacyZoneEvent(
      type: isNew ? PrivacyZoneEventType.added : PrivacyZoneEventType.updated,
      zone: zone,
    ));

    await _persist();
  }

  /// Adds multiple privacy zones.
  Future<void> addZones(List<PrivacyZone> zones) async {
    for (final zone in zones) {
      if (!zone.isValid) {
        throw ArgumentError(
            'Invalid privacy zone configuration: ${zone.identifier}');
      }
    }

    for (final zone in zones) {
      final isNew = !_zones.containsKey(zone.identifier);
      _zones[zone.identifier] = zone;

      _zoneChangesController.add(PrivacyZoneEvent(
        type: isNew ? PrivacyZoneEventType.added : PrivacyZoneEventType.updated,
        zone: zone,
      ));
    }

    await _persist();
  }

  /// Removes a privacy zone by identifier.
  Future<bool> removeZone(String identifier) async {
    final zone = _zones.remove(identifier);
    if (zone == null) return false;

    _zoneChangesController.add(PrivacyZoneEvent(
      type: PrivacyZoneEventType.removed,
      zone: zone,
    ));

    await _persist();
    return true;
  }

  /// Removes all privacy zones.
  Future<void> removeAllZones() async {
    final removed = _zones.values.toList();
    _zones.clear();

    for (final zone in removed) {
      _zoneChangesController.add(PrivacyZoneEvent(
        type: PrivacyZoneEventType.removed,
        zone: zone,
      ));
    }

    await _persist();
  }

  /// Gets a zone by identifier.
  PrivacyZone? getZone(String identifier) => _zones[identifier];

  /// Checks if a zone exists.
  bool hasZone(String identifier) => _zones.containsKey(identifier);

  /// Updates a privacy zone.
  Future<bool> updateZone(PrivacyZone zone) async {
    if (!_zones.containsKey(zone.identifier)) return false;
    if (!zone.isValid) {
      throw ArgumentError('Invalid privacy zone configuration');
    }

    _zones[zone.identifier] = zone.copyWith(updatedAt: DateTime.now());

    _zoneChangesController.add(PrivacyZoneEvent(
      type: PrivacyZoneEventType.updated,
      zone: zone,
    ));

    await _persist();
    return true;
  }

  /// Enables or disables a zone.
  Future<bool> setZoneEnabled(String identifier, bool enabled) async {
    final zone = _zones[identifier];
    if (zone == null) return false;

    return updateZone(zone.copyWith(enabled: enabled));
  }

  /// Loads zones from storage.
  Future<void> loadZones(List<PrivacyZone> zones) async {
    _zones.clear();
    for (final zone in zones) {
      _zones[zone.identifier] = zone;
    }
  }

  /// Processes a location through privacy zone rules.
  ///
  /// Returns a [PrivacyZoneResult] containing:
  /// - The original location
  /// - The processed location (obfuscated or null if excluded)
  /// - Which zones matched
  /// - Whether it was excluded or obfuscated
  PrivacyZoneResult processLocation(Location location) {
    final matchedZones = <PrivacyZone>[];

    // Find all matching enabled zones
    for (final zone in enabledZones) {
      if (zone.containsLocationObject(location)) {
        matchedZones.add(zone);
      }
    }

    if (matchedZones.isEmpty) {
      return PrivacyZoneResult(
        originalLocation: location,
        processedLocation: location,
      );
    }

    // Check for exclude action (takes precedence)
    final hasExclude =
        matchedZones.any((z) => z.action == PrivacyZoneAction.exclude);

    if (hasExclude) {
      return PrivacyZoneResult(
        originalLocation: location,
        processedLocation: null,
        matchedZones: matchedZones,
        wasExcluded: true,
      );
    }

    // Apply obfuscation using the largest obfuscation radius
    final maxObfuscationRadius = matchedZones
        .map((z) => z.obfuscationRadius)
        .reduce((a, b) => a > b ? a : b);

    final obfuscatedLocation = _obfuscateLocation(
      location,
      maxObfuscationRadius,
    );

    return PrivacyZoneResult(
      originalLocation: location,
      processedLocation: obfuscatedLocation,
      matchedZones: matchedZones,
      wasObfuscated: true,
    );
  }

  /// Processes multiple locations through privacy zone rules.
  ///
  /// Returns only usable locations (excludes locations that were excluded).
  List<Location> processLocations(List<Location> locations) {
    final result = <Location>[];

    for (final location in locations) {
      final processed = processLocation(location);
      if (processed.isUsable) {
        result.add(processed.processedLocation!);
      }
    }

    return result;
  }

  /// Checks if a location would be affected by any privacy zone.
  bool isLocationAffected(Location location) {
    for (final zone in enabledZones) {
      if (zone.containsLocationObject(location)) {
        return true;
      }
    }
    return false;
  }

  /// Gets all zones that contain the given location.
  List<PrivacyZone> getMatchingZones(Location location) {
    return enabledZones
        .where((z) => z.containsLocationObject(location))
        .toList();
  }

  /// Obfuscates a location by randomly offsetting coordinates.
  Location _obfuscateLocation(Location location, double radius) {
    // Generate random offset within radius
    final angle = _random.nextDouble() * 2 * math.pi;
    final distance = _random.nextDouble() * radius;

    // Convert to lat/lng offset (approximate)
    // 1 degree latitude ≈ 111,000 meters
    // 1 degree longitude varies by latitude
    final latOffset = (distance * math.cos(angle)) / 111000;
    final lngOffset = (distance * math.sin(angle)) /
        (111000 * math.cos(location.coords.latitude * math.pi / 180));

    final newLat =
        (location.coords.latitude + latOffset).clamp(-90.0, 90.0);
    final newLng = _normalizeLongitude(location.coords.longitude + lngOffset);

    return Location(
      uuid: location.uuid,
      timestamp: location.timestamp,
      age: location.age,
      event: location.event,
      isMoving: location.isMoving,
      isHeartbeat: location.isHeartbeat,
      coords: Coords(
        latitude: newLat,
        longitude: newLng,
        accuracy: location.coords.accuracy + radius, // Increase accuracy uncertainty
        speed: location.coords.speed,
        heading: location.coords.heading,
        altitude: location.coords.altitude,
      ),
      activity: location.activity,
      battery: location.battery,
      geofence: location.geofence,
      odometer: location.odometer,
      extras: {
        ...?location.extras,
        '_privacyObfuscated': true,
        '_privacyObfuscationRadius': radius,
      },
    );
  }

  /// Normalizes longitude to [-180, 180].
  double _normalizeLongitude(double lng) {
    while (lng > 180) {
      lng -= 360;
    }
    while (lng < -180) {
      lng += 360;
    }
    return lng;
  }

  /// Persists zones if callback is set.
  Future<void> _persist() async {
    if (_onPersist != null) {
      await _onPersist!(zones);
    }
  }

  /// Disposes of resources.
  void dispose() {
    _zoneChangesController.close();
  }
}

/// Event types for privacy zone changes.
enum PrivacyZoneEventType {
  added,
  updated,
  removed,
}

/// Event emitted when a privacy zone changes.
class PrivacyZoneEvent {
  final PrivacyZoneEventType type;
  final PrivacyZone zone;

  const PrivacyZoneEvent({
    required this.type,
    required this.zone,
  });

  JsonMap toMap() => {
        'type': type.name,
        'zone': zone.toMap(),
      };

  @override
  String toString() => 'PrivacyZoneEvent(${type.name}: ${zone.identifier})';
}
