import 'package:flutter/services.dart';
import 'package:locus/src/models.dart';
import 'package:locus/src/services.dart';
import 'package:locus/src/core/locus_channels.dart';

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
      'samples': ?samples,
      'timeout': ?timeout,
      'maximumAge': ?maximumAge,
      'persist': ?persist,
      'desiredAccuracy': ?desiredAccuracy,
      'extras': ?extras,
    };

    final result = await LocusChannels.methods.invokeMethod(
      'getCurrentPosition',
      payload,
    );
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
          .map(
            (item) => Location.fromMap((item as Map).cast<String, dynamic>()),
          )
          .toList();
    }
    return [];
  }

  /// Queries stored locations with filtering and pagination.
  static Future<List<Location>> queryLocations(LocationQuery query) async {
    final limit = query.limit;
    if (limit != null && limit <= 0) return const [];

    final arguments = <String, Object?>{
      ...query.toMap(),
      // Integer instants preserve inclusive microsecond edges and local dates.
      if (query.from case final from?)
        'from': from.toUtc().microsecondsSinceEpoch,
      if (query.to case final to?) 'to': to.toUtc().microsecondsSinceEpoch,
      'offset': query.offset < 0 ? 0 : query.offset,
      'timestampFallback': DateTime.now().toUtc().microsecondsSinceEpoch,
    };

    final Object? response;
    try {
      response = await LocusChannels.methods.invokeMethod<Object?>(
        'queryLocations',
        arguments,
      );
    } on MissingPluginException {
      throw PlatformException(
        code: 'UNSUPPORTED_NATIVE_QUERY',
        message:
            'Native location queries are unavailable. Rebuild the host app '
            'with the current Locus Android or iOS plugin.',
      );
    }

    if (response is! List<Object?>) {
      throw PlatformException(
        code: 'INVALID_RESULT',
        message: 'Expected a native location query result list.',
      );
    }

    return response
        .map((item) {
          if (item is! Map<Object?, Object?> ||
              item.keys.any((key) => key is! String)) {
            throw PlatformException(
              code: 'INVALID_RESULT',
              message: 'Expected a location map in the native query result.',
            );
          }
          return Location.fromMap(JsonMap.from(item));
        })
        .toList(growable: false);
  }

  /// Gets a summary of location history.
  static Future<LocationSummary> getLocationSummary({
    DateTime? date,
    LocationQuery? query,
  }) async {
    LocationQuery effectiveQuery;

    if (query != null) {
      effectiveQuery = query;
    } else if (date != null) {
      // Create query for the specific day
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      effectiveQuery = LocationQuery(from: startOfDay, to: endOfDay);
    } else {
      // Default to today
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      effectiveQuery = LocationQuery(from: startOfDay, to: now);
    }

    final locations = await queryLocations(effectiveQuery);
    return LocationHistoryCalculator.calculateSummary(locations);
  }

  /// Changes the motion state (moving/stationary).
  static Future<bool> changePace(bool isMoving) async {
    final result = await LocusChannels.methods.invokeMethod(
      'changePace',
      isMoving,
    );
    return result == true;
  }

  /// Sets the odometer value.
  static Future<double> setOdometer(double value) async {
    final result = await LocusChannels.methods.invokeMethod(
      'setOdometer',
      value,
    );
    return (result as num?)?.toDouble() ?? value;
  }

  /// Requests all required permissions.
  static Future<bool> requestPermission() async {
    return PermissionService.requestAll();
  }

  /// True only when the host has been granted *precise* location authority.
  /// Implementation lives natively (Android: ACCESS_FINE_LOCATION; iOS:
  /// accuracyAuthorization). On platforms that don't implement the channel
  /// method (or on errors), falls back to `false` so callers fail safe.
  static Future<bool> hasPreciseLocationPermission() async {
    try {
      final result = await LocusChannels.methods.invokeMethod<bool>(
        'hasPreciseLocationPermission',
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
