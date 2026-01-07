/// Privacy service interface for v2.0 API.
///
/// Provides a clean, organized API for privacy zone operations.
/// Access via `Locus.privacy`.
library;

import 'dart:async';

import 'package:locus/src/models.dart';
import 'package:locus/src/features/privacy/services/privacy_zone_service.dart'
    show PrivacyZoneEvent;

/// Service interface for privacy zone operations.
///
/// Privacy zones allow users to define areas where their location
/// data should be obfuscated or excluded, supporting GDPR compliance
/// and user privacy preferences.
///
/// Example:
/// ```dart
/// // Add a privacy zone around home
/// await Locus.privacy.add(PrivacyZone.create(
///   identifier: 'home',
///   latitude: 37.7749,
///   longitude: -122.4194,
///   radius: 100.0,
///   action: PrivacyZoneAction.obfuscate,
///   obfuscationRadius: 500.0,
/// ));
///
/// // Listen to privacy zone events
/// Locus.privacy.events.listen((event) {
///   print('Privacy zone ${event.zone.identifier}: ${event.action}');
/// });
/// ```
abstract class PrivacyService {
  /// Stream of privacy zone change events.
  Stream<PrivacyZoneEvent> get events;

  /// Adds a privacy zone.
  Future<void> add(PrivacyZone zone);

  /// Adds multiple privacy zones.
  Future<void> addAll(List<PrivacyZone> zones);

  /// Removes a privacy zone by identifier.
  Future<bool> remove(String identifier);

  /// Removes all privacy zones.
  Future<void> removeAll();

  /// Gets a privacy zone by identifier.
  Future<PrivacyZone?> get(String identifier);

  /// Gets all registered privacy zones.
  Future<List<PrivacyZone>> getAll();

  /// Enables or disables a privacy zone.
  Future<bool> setEnabled(String identifier, bool enabled);

  /// Subscribes to privacy zone events.
  ///
  /// Returns a [StreamSubscription] that can be cancelled to prevent memory leaks.
  ///
  /// Example:
  /// ```dart
  /// final subscription = Locus.privacy.onChange((event) {
  ///   print('Zone ${event.zone.name} was ${event.type}');
  /// });
  /// // Later, cancel the subscription
  /// subscription.cancel();
  /// ```
  StreamSubscription<PrivacyZoneEvent> onChange(void Function(PrivacyZoneEvent) callback);
}
