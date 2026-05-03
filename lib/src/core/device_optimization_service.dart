import 'dart:io';

import 'package:locus/src/core/locus_channels.dart';

/// Helpers for device-specific background execution behavior.
class DeviceOptimizationService {
  static const Map<String, String> _manufacturerLinks = {
    'xiaomi': 'https://dontkillmyapp.com/xiaomi',
    'huawei': 'https://dontkillmyapp.com/huawei',
    'samsung': 'https://dontkillmyapp.com/samsung',
    'oneplus': 'https://dontkillmyapp.com/oneplus',
    'oppo': 'https://dontkillmyapp.com/oppo',
    'vivo': 'https://dontkillmyapp.com/vivo',
    'realme': 'https://dontkillmyapp.com/realme',
    'sony': 'https://dontkillmyapp.com/sony',
    'lg': 'https://dontkillmyapp.com/lg',
    'nokia': 'https://dontkillmyapp.com/nokia',
    'asus': 'https://dontkillmyapp.com/asus',
    'lenovo': 'https://dontkillmyapp.com/lenovo',
    'motorola': 'https://dontkillmyapp.com/motorola',
  };

  /// Whether the app is exempt from battery optimizations (Android only).
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) {
      return false;
    }
    final result = await LocusChannels.methods
        .invokeMethod('isIgnoringBatteryOptimizations');
    return result == true;
  }

  /// Returns the URL for manufacturer-specific guidance (Android only).
  ///
  /// Returns `null` on non-Android platforms. The caller is responsible for
  /// launching the URL using their preferred method (e.g., url_launcher).
  static Future<String?> getManufacturerInstructionsUrl() async {
    if (!Platform.isAndroid) {
      return null;
    }
    final manufacturer = await _readManufacturer();
    final key = (manufacturer == null || manufacturer.isEmpty)
        ? 'android'
        : manufacturer.toLowerCase();
    return _manufacturerLinks[key] ?? 'https://dontkillmyapp.com/';
  }

  /// High-level guidance about OS background limits.
  static Map<String, String> getBackgroundLimitsInfo() {
    return {
      'android':
          'Doze and App Standby may restrict background work; OEMs can add '
              'aggressive task killers that require manual exemptions.',
      'ios': 'Background execution is limited; tasks may be suspended within '
          'minutes when not actively tracking location.',
    };
  }

  static Future<String?> _readManufacturer() async {
    try {
      return await LocusChannels.methods.invokeMethod<String>('getManufacturer');
    } catch (_) {
      // Channel unreachable (e.g., plugin not registered in a headless engine).
      // Caller treats null as "unknown manufacturer" and falls back to a
      // generic URL.
      return null;
    }
  }
}
