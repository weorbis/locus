import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:locus/src/core/locus_channels.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// Opens manufacturer-specific guidance (Android only).
  static Future<void> showManufacturerInstructions() async {
    if (!Platform.isAndroid) {
      return;
    }
    String manufacturer = 'android';
    final diagnosticsManufacturer = await _readManufacturerFromDiagnostics();
    if (diagnosticsManufacturer != null && diagnosticsManufacturer.isNotEmpty) {
      manufacturer = diagnosticsManufacturer.toLowerCase();
    } else {
      final info = DeviceInfoPlugin();
      try {
        final android = await info.androidInfo;
        manufacturer = android.manufacturer.toLowerCase();
      } catch (_) {
        // Fallback to generic page.
      }
    }
    final url =
        _manufacturerLinks[manufacturer] ?? 'https://dontkillmyapp.com/';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
      // Ignore and fall back to device info.
    }
    return null;
  }
}
