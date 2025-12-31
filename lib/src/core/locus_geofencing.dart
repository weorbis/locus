import 'package:locus/src/models/models.dart';
import 'locus_channels.dart';

/// Geofencing operations.
class LocusGeofencing {
  /// Adds a single geofence.
  static Future<bool> addGeofence(Geofence geofence) async {
    final result = await LocusChannels.methods
        .invokeMethod('addGeofence', geofence.toMap());
    return result == true;
  }

  /// Adds multiple geofences.
  static Future<bool> addGeofences(List<Geofence> geofences) async {
    final payload = geofences.map((g) => g.toMap()).toList();
    final result =
        await LocusChannels.methods.invokeMethod('addGeofences', payload);
    return result == true;
  }

  /// Removes a geofence by identifier.
  static Future<bool> removeGeofence(String identifier) async {
    final result =
        await LocusChannels.methods.invokeMethod('removeGeofence', identifier);
    return result == true;
  }

  /// Removes all geofences.
  static Future<bool> removeGeofences() async {
    final result = await LocusChannels.methods.invokeMethod('removeGeofences');
    return result == true;
  }

  /// Gets all registered geofences.
  static Future<List<Geofence>> getGeofences() async {
    final result = await LocusChannels.methods.invokeMethod('getGeofences');
    if (result is List) {
      return result
          .map((e) => Geofence.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  /// Gets a geofence by identifier.
  static Future<Geofence?> getGeofence(String identifier) async {
    final result =
        await LocusChannels.methods.invokeMethod('getGeofence', identifier);
    if (result is Map) {
      return Geofence.fromMap(Map<String, dynamic>.from(result));
    }
    return null;
  }

  /// Checks if a geofence exists.
  static Future<bool> geofenceExists(String identifier) async {
    final result =
        await LocusChannels.methods.invokeMethod('geofenceExists', identifier);
    return result == true;
  }

  /// Starts geofence-only mode.
  static Future<bool> startGeofences() async {
    final result = await LocusChannels.methods.invokeMethod('startGeofences');
    return result == true;
  }
}
