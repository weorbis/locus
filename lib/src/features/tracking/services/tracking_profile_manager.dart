library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:locus/src/config/config.dart';
import 'package:locus/src/shared/events.dart';
import 'package:locus/src/models.dart';

/// Event emitted when a tracking profile changes.
class ProfileChangeEvent {
  ProfileChangeEvent({
    this.previousProfile,
    required this.newProfile,
    this.reason,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  final TrackingProfile? previousProfile;
  final TrackingProfile newProfile;
  final String? reason;
  final DateTime timestamp;
}

/// Event emitted when a profile switch fails.
class ProfileSwitchError {
  ProfileSwitchError({
    required this.targetProfile,
    required this.error,
    this.stackTrace,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  final TrackingProfile targetProfile;
  final Object error;
  final StackTrace? stackTrace;
  final DateTime timestamp;
}

class TrackingProfileManager {
  TrackingProfileManager({
    required this.applyConfig,
    required Stream<GeolocationEvent<dynamic>> events,
  }) : _events = events;

  final Future<void> Function(Config config) applyConfig;
  final Stream<GeolocationEvent<dynamic>> _events;
  final Map<TrackingProfile, Config> _profiles = {};
  final List<TrackingProfileRule> _rules = [];

  TrackingProfile? _current;
  StreamSubscription<GeolocationEvent<dynamic>>? _subscription;
  DateTime? _lastSwitchAt;
  bool _isDisposed = false;

  final _profileChangeController =
      StreamController<ProfileChangeEvent>.broadcast();
  final _errorController = StreamController<ProfileSwitchError>.broadcast();

  TrackingProfile? get currentProfile => _current;

  /// Whether this manager has been disposed.
  bool get isDisposed => _isDisposed;

  /// Stream of profile change events.
  Stream<ProfileChangeEvent> get profileChanges =>
      _profileChangeController.stream;

  /// Stream of profile switch errors.
  Stream<ProfileSwitchError> get errors => _errorController.stream;

  void setProfiles(Map<TrackingProfile, Config> profiles) {
    _profiles
      ..clear()
      ..addAll(profiles);
  }

  void setRules(List<TrackingProfileRule> rules) {
    _rules
      ..clear()
      ..addAll(rules);
  }

  Future<void> setProfile(TrackingProfile profile, {String? reason}) async {
    if (_isDisposed) {
      debugPrint(
          'TrackingProfileManager: Cannot set profile, manager is disposed');
      return;
    }

    final config = _profiles[profile];
    if (config == null) {
      return;
    }
    final previousProfile = _current;
    await applyConfig(config);
    _current = profile;
    _lastSwitchAt = DateTime.now();

    // Emit profile change event (check disposed again after await)
    if (!_isDisposed) {
      _profileChangeController.add(ProfileChangeEvent(
        previousProfile: previousProfile,
        newProfile: profile,
        reason: reason,
      ));
    }
  }

  Future<void> startAutomation() async {
    if (_isDisposed) return;
    await _subscription?.cancel();
    _subscription = _events.listen(_handleEvent);
  }

  Future<void> stopAutomation() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Disposes of this manager and releases all resources.
  /// After calling dispose, this manager should not be used.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await stopAutomation();
    await _profileChangeController.close();
    await _errorController.close();
  }

  Future<void> _handleEvent(GeolocationEvent<dynamic> event) async {
    if (_isDisposed || _rules.isEmpty) {
      return;
    }
    switch (event.type) {
      case EventType.activityChange:
        await _handleActivityEvent(event.data);
        break;
      case EventType.geofence:
        await _handleGeofenceEvent(event.data);
        break;
      case EventType.location:
      case EventType.motionChange:
      case EventType.heartbeat:
      case EventType.schedule:
        await _handleSpeedEvent(event.data);
        break;
      default:
        break;
    }
  }

  Future<void> _handleActivityEvent(dynamic data) async {
    final activity = _extractActivity(data);
    if (activity == null) {
      return;
    }
    for (final rule in _rules) {
      if (rule.type != TrackingProfileRuleType.activity) {
        continue;
      }
      if (rule.activity == null) {
        continue;
      }
      if (rule.activity == activity.type) {
        await _applyRule(rule);
        return;
      }
    }
  }

  Future<void> _handleGeofenceEvent(dynamic data) async {
    if (data is! GeofenceEvent) {
      return;
    }
    for (final rule in _rules) {
      if (rule.type != TrackingProfileRuleType.geofence) {
        continue;
      }
      if (rule.geofenceAction != null && rule.geofenceAction != data.action) {
        continue;
      }
      if (rule.geofenceIdentifier != null &&
          rule.geofenceIdentifier != data.geofence.identifier) {
        continue;
      }
      await _applyRule(rule);
      return;
    }
  }

  Future<void> _handleSpeedEvent(dynamic data) async {
    final location = _extractLocation(data);
    if (location == null) {
      return;
    }
    final speedMetersPerSecond = location.coords.speed;
    if (speedMetersPerSecond == null) {
      return;
    }
    final speedKph = speedMetersPerSecond * 3.6;

    TrackingProfileRule? bestMatch;
    TrackingProfileRule? bestSpeedAbove;
    TrackingProfileRule? bestSpeedBelow;

    // 1. Find the strictiest match for each type
    for (final rule in _rules) {
      if (rule.type == TrackingProfileRuleType.speedAbove &&
          rule.speedKph != null &&
          speedKph >= rule.speedKph!) {
        if (bestSpeedAbove == null ||
            rule.speedKph! > bestSpeedAbove.speedKph!) {
          bestSpeedAbove = rule;
        }
      } else if (rule.type == TrackingProfileRuleType.speedBelow &&
          rule.speedKph != null &&
          speedKph <= rule.speedKph!) {
        if (bestSpeedBelow == null ||
            rule.speedKph! < bestSpeedBelow.speedKph!) {
          bestSpeedBelow = rule;
        }
      }
    }

    // 2. Pick the winner based on original list priority (index)
    // Since we iterated in order, we just need to know which of the "best" candidates appears first.
    // Actually, simply matching the *specific* best instances is enough?
    //
    // IF we have >10 (index 0) and >100 (index 5). Speed 120.
    // bestSpeedAbove is >100.
    // The code below should select >100.

    // IF we have >10 (index 0) and <50 (index 1). Speed 30.
    // bestSpeedAbove is >10. bestSpeedBelow is <50.
    // Logic: Who wins?
    // We want the one that appeared first in the config.
    // >10 is at index 0. <50 is at index 1.
    // So >10 should win.

    if (bestSpeedAbove != null && bestSpeedBelow != null) {
      // Find which one comes first
      final indexAbove = _rules.indexOf(bestSpeedAbove);
      final indexBelow = _rules.indexOf(bestSpeedBelow);
      bestMatch = indexAbove < indexBelow ? bestSpeedAbove : bestSpeedBelow;
    } else {
      bestMatch = bestSpeedAbove ?? bestSpeedBelow;
    }

    if (bestMatch != null) {
      await _applyRule(bestMatch);
    }
  }

  Future<void> _applyRule(TrackingProfileRule rule) async {
    if (_isDisposed) return;
    if (_current == rule.profile) {
      return;
    }
    if (!_shouldSwitch(rule.cooldownSeconds)) {
      return;
    }
    await setProfile(
      rule.profile,
      reason: 'Automation: ${rule.type.name}',
    ).catchError((Object e, StackTrace stack) {
      debugPrint('TrackingProfileManager: Failed to switch profile: $e');
      // Emit error to stream for observability (if not disposed)
      if (!_isDisposed) {
        _errorController.add(ProfileSwitchError(
          targetProfile: rule.profile,
          error: e,
          stackTrace: stack,
        ));
      }
    });
  }

  bool _shouldSwitch(int cooldownSeconds) {
    final lastSwitch = _lastSwitchAt;
    if (lastSwitch == null) {
      return true;
    }
    return DateTime.now().difference(lastSwitch).inSeconds >= cooldownSeconds;
  }

  Activity? _extractActivity(dynamic data) {
    if (data is Activity) {
      return data;
    }
    if (data is Location && data.activity != null) {
      return data.activity;
    }
    if (data is Map) {
      return Activity.fromMap(Map<String, dynamic>.from(data));
    }
    return null;
  }

  Location? _extractLocation(dynamic data) {
    if (data is Location) {
      return data;
    }
    if (data is Map && data['coords'] is Map) {
      return Location.fromMap(Map<String, dynamic>.from(data));
    }
    return null;
  }
}
