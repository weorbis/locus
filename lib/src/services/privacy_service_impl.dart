/// Privacy service implementation for v2.0 API.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:locus/src/models.dart';
import 'package:locus/src/core/locus_interface.dart';
import 'package:locus/src/services/privacy_service.dart';
import 'package:locus/src/features/privacy/services/privacy_zone_service.dart'
    show PrivacyZoneEvent;

/// Implementation of [PrivacyService] using method channel.
class PrivacyServiceImpl implements PrivacyService {
  /// Creates a privacy service with the given Locus interface provider.
  PrivacyServiceImpl(this._instanceProvider);

  final LocusInterface Function() _instanceProvider;

  LocusInterface get _instance => _instanceProvider();

  @override
  Stream<PrivacyZoneEvent> get events => _instance.privacyZoneEvents;

  @override
  Future<void> add(PrivacyZone zone) => _instance.addPrivacyZone(zone);

  @override
  Future<void> addAll(List<PrivacyZone> zones) =>
      _instance.addPrivacyZones(zones);

  @override
  Future<bool> remove(String identifier) =>
      _instance.removePrivacyZone(identifier);

  @override
  Future<void> removeAll() => _instance.removeAllPrivacyZones();

  @override
  Future<PrivacyZone?> get(String identifier) =>
      _instance.getPrivacyZone(identifier);

  @override
  Future<List<PrivacyZone>> getAll() => _instance.getPrivacyZones();

  @override
  Future<bool> setEnabled(String identifier, bool enabled) =>
      _instance.setPrivacyZoneEnabled(identifier, enabled);

  @override
  StreamSubscription<PrivacyZoneEvent> onChange(void Function(PrivacyZoneEvent) callback) {
    return _instance.privacyZoneEvents.listen(
      callback,
      onError: (error, stackTrace) {
        debugPrint('[PrivacyService] Error in privacyZoneEvents stream: $error');
      },
    );
  }
}
