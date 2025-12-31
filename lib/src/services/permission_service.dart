library;

import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Service for handling location and activity permissions.
class PermissionService {
  const PermissionService._();

  /// Requests all required permissions for background geolocation.
  ///
  /// On Android: location (when in use + always) and activity recognition.
  /// On iOS: location (when in use + always) and motion sensors.
  ///
  /// Returns `true` if all required permissions are granted.
  static Future<bool> requestAll() async {
    if (Platform.isAndroid) {
      return _requestAndroidPermissions();
    }
    return _requestIOSPermissions();
  }

  static Future<bool> _requestAndroidPermissions() async {
    final whenInUse = await Permission.locationWhenInUse.request();
    if (!whenInUse.isGranted) {
      return false;
    }
    final location = await Permission.locationAlways.request();
    final activity = await Permission.activityRecognition.request();
    final notification = await Permission.notification.request();
    return location.isGranted && activity.isGranted && notification.isGranted;
  }

  static Future<bool> _requestIOSPermissions() async {
    final whenInUse = await Permission.locationWhenInUse.request();
    if (!whenInUse.isGranted) {
      return false;
    }
    final location = await Permission.locationAlways.request();
    final motion = await Permission.sensors.request();
    return location.isGranted && motion.isGranted;
  }

  /// Checks if location permission is granted (when in use).
  static Future<bool> hasLocationPermission() async {
    return await Permission.locationWhenInUse.isGranted;
  }

  /// Checks if always location permission is granted.
  static Future<bool> hasAlwaysLocationPermission() async {
    return await Permission.locationAlways.isGranted;
  }

  /// Checks if activity/motion permission is granted.
  static Future<bool> hasActivityPermission() async {
    if (Platform.isAndroid) {
      return await Permission.activityRecognition.isGranted;
    }
    return await Permission.sensors.isGranted;
  }

  /// Opens the app settings page.
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }
}
