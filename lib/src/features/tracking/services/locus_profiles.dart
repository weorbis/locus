import 'dart:async';
import 'package:locus/src/config/config.dart';
import 'package:locus/src/models.dart';
import 'package:locus/src/services.dart';
import 'package:locus/src/core/locus_config.dart';
import 'package:locus/src/core/locus_streams.dart';

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
      await _profileManager!.startAutomation();
    } else {
      await _profileManager!.stopAutomation();
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
  static Future<void> startTrackingAutomation() async {
    await _profileManager?.startAutomation();
  }

  /// Disables automation rules for tracking profiles.
  static Future<void> stopTrackingAutomation() async {
    await _profileManager?.stopAutomation();
  }

  /// Clears tracking profiles and automation rules.
  static Future<void> clearTrackingProfiles() async {
    await _profileManager?.dispose();
    _profileManager = null;
  }
}
