/// Mock implementation of PrivacyService for testing.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:locus/locus.dart';

/// Mock privacy service with controllable behavior.
///
/// Example:
/// ```dart
/// final mock = MockPrivacyService();
/// 
/// // Add privacy zone
/// await mock.add(PrivacyZone.create(
///   identifier: 'home',
///   latitude: 37.4219,
///   longitude: -122.084,
///   radius: 100,
///   action: PrivacyZoneAction.obfuscate,
/// ));
/// 
/// // Check if location is in privacy zone
/// final isPrivate = mock.isLocationInPrivacyZone(location);
/// 
/// // Apply privacy rules
/// final filtered = mock.applyPrivacy(location);
/// ```
class MockPrivacyService implements PrivacyService {
  final List<PrivacyZone> _zones = [];
  final _eventsController = StreamController<PrivacyZoneEvent>.broadcast();
  
  final List<void Function(PrivacyZoneEvent)> _callbacks = [];

  @override
  Stream<PrivacyZoneEvent> get events => _eventsController.stream;

  @override
  Future<void> add(PrivacyZone zone) async {
    _zones.removeWhere((z) => z.identifier == zone.identifier);
    _zones.add(zone);
    
    _emitEvent(PrivacyZoneEvent(
      type: PrivacyZoneEventType.added,
      zone: zone,
    ));
  }

  @override
  Future<void> addAll(List<PrivacyZone> zones) async {
    for (final zone in zones) {
      await add(zone);
    }
  }

  @override
  Future<bool> remove(String identifier) async {
    final zone = _zones.cast<PrivacyZone?>().firstWhere(
          (z) => z?.identifier == identifier,
          orElse: () => null,
        );
    
    if (zone != null) {
      _zones.removeWhere((z) => z.identifier == identifier);
      _emitEvent(PrivacyZoneEvent(
        type: PrivacyZoneEventType.removed,
        zone: zone,
      ));
      return true;
    }
    return false;
  }

  @override
  Future<void> removeAll() async {
    _zones.clear();
    _emitEvent(PrivacyZoneEvent(
      type: PrivacyZoneEventType.removed,
      zone: PrivacyZone.create(
        identifier: 'all',
        latitude: 0,
        longitude: 0,
        radius: 0,
      ),
    ));
  }

  @override
  Future<PrivacyZone?> get(String identifier) async {
    try {
      return _zones.firstWhere((z) => z.identifier == identifier);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<PrivacyZone>> getAll() async {
    return List.unmodifiable(_zones);
  }

  @override
  Future<bool> setEnabled(String identifier, bool enabled) async {
    final zone = await get(identifier);
    if (zone == null) return false;
    
    // Update the zone (create a new one with updated enabled status)
    final updatedZone = PrivacyZone.create(
      identifier: zone.identifier,
      latitude: zone.latitude,
      longitude: zone.longitude,
      radius: zone.radius,
      enabled: enabled,
      action: zone.action,
      obfuscationRadius: zone.obfuscationRadius,
    );
    
    await add(updatedZone);
    return true;
  }

  @override
  StreamSubscription<PrivacyZoneEvent> onChange(void Function(PrivacyZoneEvent) callback) {
    _callbacks.add(callback);
    return _eventsController.stream.listen(callback);
  }

  void _emitEvent(PrivacyZoneEvent event) {
    _eventsController.add(event);
    for (final callback in _callbacks) {
      callback(event);
    }
  }

  // ============================================================
  // Test Helpers
  // ============================================================

  /// Checks if a location is within any privacy zone.
  bool isLocationInPrivacyZone(Location location) {
    for (final zone in _zones) {
      if (!zone.enabled) continue;
      
      final distance = _calculateDistance(
        zone.latitude,
        zone.longitude,
        location.coords.latitude,
        location.coords.longitude,
      );
      
      if (distance <= zone.radius) {
        return true;
      }
    }
    return false;
  }

  /// Gets the privacy zone containing the location, if any.
  PrivacyZone? getZoneForLocation(Location location) {
    for (final zone in _zones) {
      if (!zone.enabled) continue;
      
      final distance = _calculateDistance(
        zone.latitude,
        zone.longitude,
        location.coords.latitude,
        location.coords.longitude,
      );
      
      if (distance <= zone.radius) {
        return zone;
      }
    }
    return null;
  }

  /// Applies privacy rules to a location.
  ///
  /// Returns the location with privacy applied based on the zone's action.
  Location? applyPrivacy(Location location) {
    final zone = getZoneForLocation(location);
    if (zone == null) return location;
    
    switch (zone.action) {
      case PrivacyZoneAction.exclude:
        return null; // Location should be excluded
      
      case PrivacyZoneAction.obfuscate:
        // Obfuscate by adding random offset
        final random = math.Random();
        final radius = zone.obfuscationRadius;
        final angle = random.nextDouble() * 2 * math.pi;
        final distance = random.nextDouble() * radius;
        
        final latOffset = (distance / 111000) * math.cos(angle);
        final lngOffset = (distance / 111000) * math.sin(angle) /
            math.cos(location.coords.latitude * math.pi / 180);
        
        return Location(
          uuid: location.uuid,
          timestamp: location.timestamp,
          coords: Coords(
            latitude: location.coords.latitude + latOffset,
            longitude: location.coords.longitude + lngOffset,
            accuracy: math.max(location.coords.accuracy, radius),
            speed: location.coords.speed,
            heading: location.coords.heading,
            altitude: location.coords.altitude,
          ),
          isMoving: location.isMoving,
          odometer: location.odometer,
          activity: location.activity,
          battery: location.battery,
          extras: location.extras,
        );
    }
  }

  /// Triggers a privacy zone entry event.
  void triggerEntry(String identifier, Location location) {
    final zone = _zones.cast<PrivacyZone?>().firstWhere(
          (z) => z?.identifier == identifier,
          orElse: () => null,
        );
    
    if (zone != null) {
      _emitEvent(PrivacyZoneEvent(
        type: PrivacyZoneEventType.added,
        zone: zone,
      ));
    }
  }

  /// Triggers a privacy zone exit event.
  void triggerExit(String identifier, Location location) {
    final zone = _zones.cast<PrivacyZone?>().firstWhere(
          (z) => z?.identifier == identifier,
          orElse: () => null,
        );
    
    if (zone != null) {
      _emitEvent(PrivacyZoneEvent(
        type: PrivacyZoneEventType.removed,
        zone: zone,
      ));
    }
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  /// Disposes of resources.
  Future<void> dispose() async {
    await _eventsController.close();
    _callbacks.clear();
  }
}
