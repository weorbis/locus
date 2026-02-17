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
          .map(
              (item) => Location.fromMap((item as Map).cast<String, dynamic>()))
          .toList();
    }
    return [];
  }

  /// Queries stored locations with filtering and pagination.
  static Future<List<Location>> queryLocations(LocationQuery query) async {
    // Pull only what is needed based on limit/offset to reduce memory use
    final limit = query.limit;
    final offset = query.offset;
    final fetchLimit = limit != null ? limit + offset : null;

    final fetched = await getLocations(limit: fetchLimit);
    final clampedOffset = offset.clamp(0, fetched.length);
    final end = limit != null
        ? (clampedOffset + limit).clamp(0, fetched.length)
        : fetched.length;
    final sliced = fetched.sublist(clampedOffset, end);

    final adjustedQuery = LocationQuery(
      from: query.from,
      to: query.to,
      minAccuracy: query.minAccuracy,
      maxAccuracy: query.maxAccuracy,
      isMoving: query.isMoving,
      bounds: query.bounds,
      sortOrder: query.sortOrder,
      offset: 0,
      limit: null,
    );

    return adjustedQuery.apply(sliced);
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
