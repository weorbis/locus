/// Custom exceptions for Locus SDK to provide clear error messages.
library;

/// Base class for all Locus exceptions.
abstract class LocusException implements Exception {
  const LocusException(this.message, {this.suggestion});

  /// Human-readable error message.
  final String message;

  /// Suggestion for how to fix the issue.
  final String? suggestion;

  @override
  String toString() {
    final buffer = StringBuffer('LocusException: $message');
    if (suggestion != null) {
      buffer.write('\n  Suggestion: $suggestion');
    }
    return buffer.toString();
  }
}

/// Thrown when Locus methods are called before [Locus.ready].
class NotInitializedException extends LocusException {
  const NotInitializedException()
      : super(
          'Locus is not initialized. You must call Locus.ready() before using other methods.',
          suggestion:
              'Add "await Locus.ready(Config.balanced());" in your main() or initState().',
        );
}

/// Thrown when HTTP sync is attempted without a URL configured.
class SyncUrlNotConfiguredException extends LocusException {
  const SyncUrlNotConfiguredException()
      : super(
          'HTTP sync URL is not configured. Sync operations will be skipped.',
          suggestion:
              'Set the url in Config: Config.balanced(url: "https://api.example.com/locations")',
        );
}

/// Thrown when headless task registration fails.
class HeadlessRegistrationException extends LocusException {
  const HeadlessRegistrationException({String? reason})
      : super(
          'Failed to register headless task. ${reason ?? "Callback handles could not be obtained."}',
          suggestion:
              'Ensure your headless callback is a top-level or static function with @pragma("vm:entry-point").',
        );
}

/// Thrown when setSyncBodyBuilder is called with a closure in headless mode.
class InvalidSyncBodyBuilderException extends LocusException {
  const InvalidSyncBodyBuilderException()
      : super(
          'Sync body builder for headless mode must be a top-level or static function.',
          suggestion: '''
Move your builder to a top-level function:

@pragma('vm:entry-point')
Future<Map<String, dynamic>> buildSyncBody(SyncBodyContext ctx) async {
  return {'locations': ctx.locations.map((l) => l.toJson()).toList()};
}

await Locus.registerHeadlessSyncBodyBuilder(buildSyncBody);''',
        );
}

/// Thrown when permissions are insufficient for the requested operation.
class InsufficientPermissionsException extends LocusException {
  const InsufficientPermissionsException(
      {required String operation, String? currentStatus})
      : super(
          'Insufficient permissions for $operation. ${currentStatus != null ? "Current status: $currentStatus" : ""}',
          suggestion:
              'Request location permissions using Locus.requestPermission() or PermissionAssistant.',
        );
}

/// Thrown when geofence limit is exceeded.
class GeofenceLimitExceededException extends LocusException {
  const GeofenceLimitExceededException(
      {required int limit, required int attempted})
      : super(
          'Cannot add geofence. Maximum limit of $limit geofences reached (attempted: $attempted).',
          suggestion:
              'Remove unused geofences with Locus.removeGeofence(identifier) before adding new ones.',
        );
}

/// Thrown when tracking profiles are used without being configured.
class TrackingProfilesNotConfiguredException extends LocusException {
  const TrackingProfilesNotConfiguredException()
      : super(
          'Tracking profiles have not been configured.',
          suggestion:
              'Call Locus.setTrackingProfiles() before using profile-related methods.',
        );
}

/// Thrown when a geofence workflow references an invalid geofence.
class InvalidGeofenceWorkflowException extends LocusException {
  const InvalidGeofenceWorkflowException(
      {required String workflowId, String? reason})
      : super(
          'Invalid geofence workflow "$workflowId". ${reason ?? ""}',
          suggestion:
              'Ensure all geofences referenced in the workflow are registered.',
        );
}

/// Thrown when native plugin is not available.
class PluginNotAvailableException extends LocusException {
  const PluginNotAvailableException({String? platform})
      : super(
          'Locus plugin is not available${platform != null ? " on $platform" : ""}.',
          suggestion:
              'Ensure the Locus package is properly installed and the app is running on a real device or emulator.',
        );
}

/// Provides helpful logging for common issues.
class LocusDiagnosticMessages {
  LocusDiagnosticMessages._();

  /// Message when sync is skipped due to missing URL.
  static const String syncSkippedNoUrl =
      '[Locus] Sync skipped: No URL configured. Set Config.url to enable HTTP sync.';

  /// Message when sync is paused due to 401.
  static const String syncPaused401 =
      '[Locus] Sync paused: Received 401 Unauthorized. Call Locus.resumeSync() after refreshing your auth token.';

  /// Message when headless task registration fails.
  static const String headlessRegistrationFailed =
      '[Locus] Headless task registration failed. Ensure your callback is a top-level function with @pragma("vm:entry-point").';

  /// Message when autoSync is enabled but batchSync is false.
  static const String autoSyncWithoutBatch =
      '[Locus] Warning: autoSync=true but batchSync=false. Each location will trigger an immediate HTTP request. Consider enabling batchSync for efficiency.';

  /// Message when extras is set but httpRootProperty is not.
  static const String extrasWithoutRootProperty =
      '[Locus] Note: extras configured but httpRootProperty is not set. Locations will be sent under "locations" key.';

  /// Message when tracking is started without permissions.
  static const String trackingWithoutPermissions =
      '[Locus] Warning: Tracking started but location permissions may not be granted. Call Locus.requestPermission() first.';

  /// Returns a helpful message for common error codes from the native side.
  static String? messageForNativeError(int errorCode) {
    switch (errorCode) {
      case 1:
        return '[Locus] Location services are disabled. Guide the user to Settings > Location.';
      case 2:
        return '[Locus] Location permission denied. Request permission with Locus.requestPermission().';
      case 3:
        return '[Locus] Background location permission denied. Use PermissionAssistant for "Always" permission.';
      case 4:
        return '[Locus] Network unavailable. Locations are being queued for later sync.';
      case 5:
        return '[Locus] Storage error. Check device storage capacity.';
      default:
        return null;
    }
  }
}
