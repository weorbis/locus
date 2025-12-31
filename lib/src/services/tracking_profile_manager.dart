library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:locus/src/config/config.dart';
import 'package:locus/src/events/events.dart';
import 'package:locus/src/models/models.dart';

/// Event emitted when a tracking profile changes.
class ProfileChangeEvent {
  final TrackingProfile? previousProfile;
  final TrackingProfile newProfile;
  final String? reason;
  final DateTime timestamp;

  ProfileChangeEvent({
    this.previousProfile,
    required this.newProfile,
    this.reason,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Event emitted when a profile switch fails.
class ProfileSwitchError {
  final TrackingProfile targetProfile;
  final Object error;
  final StackTrace? stackTrace;
  final DateTime timestamp;

  ProfileSwitchError({
    required this.targetProfile,
    required this.error,
    this.stackTrace,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
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

  final _profileChangeController =
      StreamController<ProfileChangeEvent>.broadcast();
  final _errorController = StreamController<ProfileSwitchError>.broadcast();

  TrackingProfile? get currentProfile => _current;

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
    final config = _profiles[profile];
    if (config == null) {
      return;
    }
    final previousProfile = _current;
    await applyConfig(config);
    _current = profile;
    _lastSwitchAt = DateTime.now();

    // Emit profile change event
    _profileChangeController.add(ProfileChangeEvent(
      previousProfile: previousProfile,
      newProfile: profile,
      reason: reason,
    ));
  }

  void startAutomation() {
    _subscription?.cancel();
    _subscription = _events.listen(_handleEvent);
  }

  void stopAutomation() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stopAutomation();
    _profileChangeController.close();
    _errorController.close();
  }

  void _handleEvent(GeolocationEvent<dynamic> event) {
    if (_rules.isEmpty) {
      return;
    }
    switch (event.type) {
      case EventType.activityChange:
        _handleActivityEvent(event.data);
        break;
      case EventType.geofence:
        _handleGeofenceEvent(event.data);
        break;
      case EventType.location:
      case EventType.motionChange:
      case EventType.heartbeat:
      case EventType.schedule:
        _handleSpeedEvent(event.data);
        break;
      default:
        break;
    }
  }

  void _handleActivityEvent(dynamic data) {
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
        _applyRule(rule);
        return;
      }
    }
  }

  void _handleGeofenceEvent(dynamic data) {
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
      _applyRule(rule);
      return;
    }
  }

  void _handleSpeedEvent(dynamic data) {
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
      _applyRule(bestMatch);
    }
  }

  void _applyRule(TrackingProfileRule rule) {
    if (_current == rule.profile) {
      return;
    }
    if (!_shouldSwitch(rule.cooldownSeconds)) {
      return;
    }
    setProfile(
      rule.profile,
      reason: 'Automation: ${rule.type.name}',
    ).catchError((Object e, StackTrace stack) {
      debugPrint('TrackingProfileManager: Failed to switch profile: $e');
      // Emit error to stream for observability
      _errorController.add(ProfileSwitchError(
        targetProfile: rule.profile,
        error: e,
        stackTrace: stack,
      ));
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
