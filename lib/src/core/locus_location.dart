import 'package:flutter/services.dart';
import 'package:locus/src/models/models.dart';
import 'package:locus/src/services/services.dart';
import 'locus_channels.dart';

/// Location operations.
class LocusLocation {
  /// Gets the current position.
  static Future<Location> getCurrentPosition({
    int? samples,
    int? timeout,
    int? maximumAge,
    bool? persist,
    int? desiredAccuracy,
    JsonMap? extras,
  }) async {
    final payload = <String, dynamic>{
      if (samples != null) 'samples': samples,
      if (timeout != null) 'timeout': timeout,
      if (maximumAge != null) 'maximumAge': maximumAge,
      if (persist != null) 'persist': persist,
      if (desiredAccuracy != null) 'desiredAccuracy': desiredAccuracy,
      if (extras != null) 'extras': extras,
    };

    final result =
        await LocusChannels.methods.invokeMethod('getCurrentPosition', payload);
    if (result is Map) {
      return Location.fromMap(Map<String, dynamic>.from(result));
    }
    throw PlatformException(
      code: 'INVALID_RESULT',
      message:
          'Expected location payload from native layer, got ${result.runtimeType}.',
      details: result,
    );
  }

  /// Gets stored locations.
  static Future<List<Location>> getLocations({int? limit}) async {
    final result = await LocusChannels.methods.invokeMethod(
      'getLocations',
      limit == null ? null : {'limit': limit},
    );
    if (result is List) {
      return result
          .map((item) =>
              Location.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList();
    }
    return [];
  }

  /// Changes the motion state (moving/stationary).
  static Future<bool> changePace(bool isMoving) async {
    final result =
        await LocusChannels.methods.invokeMethod('changePace', isMoving);
    return result == true;
  }

  /// Sets the odometer value.
  static Future<double> setOdometer(double value) async {
    final result =
        await LocusChannels.methods.invokeMethod('setOdometer', value);
    return (result as num?)?.toDouble() ?? value;
  }

  /// Requests all required permissions.
  static Future<bool> requestPermission() async {
    return PermissionService.requestAll();
  }
}
