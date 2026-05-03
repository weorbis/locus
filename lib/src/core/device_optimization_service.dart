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
    final diagnosticsManufacturer = await _readManufacturerFromDiagnostics();
    final manufacturer =
        (diagnosticsManufacturer == null || diagnosticsManufacturer.isEmpty)
            ? 'android'
            : diagnosticsManufacturer.toLowerCase();
    return _manufacturerLinks[manufacturer] ?? 'https://dontkillmyapp.com/';
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

  static Future<String?> _readManufacturerFromDiagnostics() async {
    try {
      final result =
          await LocusChannels.methods.invokeMethod('getDiagnosticsMetadata');
      if (result is Map) {
        final metadata = Map<String, dynamic>.from(result);
        final manufacturer = metadata['manufacturer'] as String?;
        if (manufacturer != null && manufacturer.isNotEmpty) {
          return manufacturer;
        }
      }
    } catch (_) {
      // Ignore; caller treats null as "unknown manufacturer".
    }
    return null;
  }
}
