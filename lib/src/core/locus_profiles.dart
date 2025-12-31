import 'dart:async';
import 'package:locus/src/config/config.dart';
import 'package:locus/src/models/models.dart';
import 'package:locus/src/services/services.dart';
import 'locus_config.dart';
import 'locus_streams.dart';

/// Tracking Profiles management.
class LocusProfiles {
  static TrackingProfileManager? _profileManager;

  static TrackingProfile? get currentTrackingProfile =>
      _profileManager?.currentProfile;

  /// Registers tracking profiles and optional automation rules.
  static Future<void> setTrackingProfiles(
    Map<TrackingProfile, Config> profiles, {
    TrackingProfile? initialProfile,
    List<TrackingProfileRule> rules = const [],
    bool enableAutomation = false,
  }) async {
    _profileManager ??= TrackingProfileManager(
      applyConfig: LocusConfig.setConfig,
      events: LocusStreams.events,
    );
    _profileManager!
      ..setProfiles(profiles)
      ..setRules(rules);
    if (initialProfile != null) {
      await _profileManager!.setProfile(initialProfile);
    }
    if (enableAutomation) {
      _profileManager!.startAutomation();
    } else {
      _profileManager!.stopAutomation();
    }
  }

  /// Applies a specific tracking profile.
  static Future<void> setTrackingProfile(TrackingProfile profile) async {
    _profileManager ??= TrackingProfileManager(
      applyConfig: LocusConfig.setConfig,
      events: LocusStreams.events,
    );
    await _profileManager!.setProfile(profile);
  }

  /// Enables automation rules for tracking profiles.
  static void startTrackingAutomation() {
    _profileManager?.startAutomation();
  }

  /// Disables automation rules for tracking profiles.
  static void stopTrackingAutomation() {
    _profileManager?.stopAutomation();
  }

  /// Clears tracking profiles and automation rules.
  static void clearTrackingProfiles() {
    _profileManager?.dispose();
    _profileManager = null;
  }
}
