/// Custom exceptions for Locus SDK to provide clear error messages.
library;

import 'package:locus/locus.dart';

/// Base class for all Locus exceptions.
///
/// All custom exceptions in the Locus SDK extend this base class to provide
/// consistent error messaging and helpful suggestions for resolution.
abstract class LocusException implements Exception {
  /// Creates a [LocusException] with a [message] and optional [suggestion].
  ///
  /// The [message] should describe what went wrong, while [suggestion] provides
  /// actionable steps to resolve the issue.
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
///
/// This exception indicates that an attempt was made to use Locus SDK methods
/// (such as `Locus.start()` or `Locus.getCurrentPosition()`) before the SDK was
/// properly initialized.
///
/// Example scenarios:
/// - Calling `Locus.startTracking()` immediately in `main()` without awaiting `Locus.ready()`
/// - Accessing Locus methods in a route that loads before initialization completes
/// - Using Locus in a background task without ensuring initialization
class NotInitializedException extends LocusException {
  /// Creates a [NotInitializedException].
  ///
  /// Thrown when attempting to use Locus SDK functionality before calling
  /// and awaiting [Locus.ready].
  ///
  /// Example:
  /// ```dart
  /// // ❌ This will throw NotInitializedException
  /// await Locus.start();

  /// // ✅ Correct usage
  /// await Locus.ready(Config.balanced());
  /// await Locus.start();
  /// ```
  const NotInitializedException()
      : super(
          'Locus is not initialized. You must call Locus.ready() before using other methods.',
          suggestion:
              'Add "await Locus.ready(Config.balanced());" in your main() or initState().',
        );
}

/// Thrown when HTTP sync is attempted without a URL configured.
///
/// This exception is raised when automatic or manual sync operations are triggered
/// but no HTTP endpoint has been configured to receive location data.
///
/// Example scenarios:
/// - `autoSync: true` is set but `url` is null
/// - Calling `Locus.sync()` manually without configuring a URL
/// - Headless sync triggered with missing URL configuration
class SyncUrlNotConfiguredException extends LocusException {
  /// Creates a [SyncUrlNotConfiguredException].
  ///
  /// Thrown when sync operations are attempted without a configured HTTP endpoint.
  ///
  /// Example:
  /// ```dart
  /// // ❌ This configuration will cause sync to fail
  /// await Locus.ready(Config.balanced(
  ///   autoSync: true,
  ///   // url is missing!
  /// ));
  ///
  /// // ✅ Correct configuration
  /// await Locus.ready(Config.balanced(
  ///   autoSync: true,
  ///   url: 'https://api.example.com/locations',
  /// ));
  /// ```
  const SyncUrlNotConfiguredException()
      : super(
          'HTTP sync URL is not configured. Sync operations will be skipped.',
          suggestion:
              'Set the url in Config: Config.balanced(url: "https://api.example.com/locations")',
        );
}

/// Thrown when headless task registration fails.
///
/// This exception occurs when attempting to register a headless callback for
/// background execution, but the registration process fails. Common causes include
/// using closures instead of top-level functions or missing required pragmas.
///
/// Example scenarios:
/// - Using an instance method or closure as a headless callback
/// - Missing `@pragma('vm:entry-point')` annotation
/// - Callback function not accessible from isolate
class HeadlessRegistrationException extends LocusException {
  /// Creates a [HeadlessRegistrationException] with an optional [reason].
  ///
  /// The [reason] parameter provides additional context about why registration failed.
  ///
  /// Example:
  /// ```dart
  /// // ❌ This will throw HeadlessRegistrationException
  /// void _myCallback(Location loc) { }
  /// await Locus.registerHeadlessLocationCallback(_myCallback);
  ///
  /// // ✅ Correct usage
  /// @pragma('vm:entry-point')
  /// void myHeadlessCallback(Location loc) {
  ///   // Handle location in background
  /// }
  /// await Locus.registerHeadlessLocationCallback(myHeadlessCallback);
  /// ```
  const HeadlessRegistrationException({String? reason})
      : super(
          'Failed to register headless task. ${reason ?? "Callback handles could not be obtained."}',
          suggestion:
              'Ensure your headless callback is a top-level or static function with @pragma("vm:entry-point").',
        );
}

/// Thrown when setSyncBodyBuilder is called with a closure in headless mode.
///
/// This exception is raised when attempting to register a sync body builder that
/// cannot be serialized for headless execution. Headless callbacks must be
/// top-level or static functions to be accessible across isolates.
///
/// Example scenarios:
/// - Passing an anonymous function to `registerHeadlessSyncBodyBuilder`
/// - Using an instance method as a sync body builder
/// - Registering a closure that captures local variables
class InvalidSyncBodyBuilderException extends LocusException {
  /// Creates an [InvalidSyncBodyBuilderException].
  ///
  /// Thrown when an invalid sync body builder is registered for headless mode.
  ///
  /// Example:
  /// ```dart
  /// // ❌ This will throw InvalidSyncBodyBuilderException
  /// await Locus.registerHeadlessSyncBodyBuilder(
  ///   (ctx) async => {'data': ctx.locations}
  /// );
  ///
  /// // ✅ Correct usage
  /// @pragma('vm:entry-point')
  /// Future<Map<String, dynamic>> buildSyncBody(SyncBodyContext ctx) async {
  ///   return {'locations': ctx.locations.map((l) => l.toJson()).toList()};
  /// }
  /// await Locus.registerHeadlessSyncBodyBuilder(buildSyncBody);
  /// ```
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
///
/// This exception indicates that the app lacks the necessary location permissions
/// to perform the requested operation. Different operations require different
/// permission levels (e.g., "When In Use" vs "Always").
///
/// Example scenarios:
/// - Starting tracking without any location permissions
/// - Attempting background tracking with only "When In Use" permission
/// - Accessing location on a platform where permissions were denied
class InsufficientPermissionsException extends LocusException {
  /// Creates an [InsufficientPermissionsException].
  ///
  /// The [operation] parameter describes what was being attempted, and
  /// [currentStatus] optionally provides the current permission state.
  ///
  /// Example:
  /// ```dart
  /// // User denies permission, then tries to start tracking
  /// final permission = await Locus.requestPermission();
  /// if (permission != LocationPermission.always) {
  ///   // This might throw InsufficientPermissionsException
  ///   await Locus.startTracking();
  /// }
  ///
  /// // ✅ Better approach
  /// final permission = await Locus.requestPermission();
  /// if (permission == LocationPermission.always ||
  ///     permission == LocationPermission.whileInUse) {
  ///   await Locus.startTracking();
  /// } else {
  ///   // Handle permission denial gracefully
  /// }
  /// ```
  const InsufficientPermissionsException(
      {required String operation, String? currentStatus})
      : super(
          'Insufficient permissions for $operation. ${currentStatus != null ? "Current status: $currentStatus" : ""}',
          suggestion:
              'Request location permissions using Locus.requestPermission() or PermissionAssistant.',
        );
}

/// Thrown when geofence limit is exceeded.
///
/// This exception occurs when attempting to register more geofences than the
/// platform allows. iOS typically allows 20 geofences, while Android may allow
/// up to 100 depending on the device and OS version.
///
/// Example scenarios:
/// - Adding 21st geofence on iOS without removing existing ones
/// - Bulk geofence registration exceeding platform limits
/// - Not cleaning up old geofences before adding new ones
class GeofenceLimitExceededException extends LocusException {
  /// Creates a [GeofenceLimitExceededException].
  ///
  /// The [limit] parameter specifies the maximum allowed geofences, and
  /// [attempted] indicates how many were being added.
  ///
  /// Example:
  /// ```dart
  /// // ❌ This might throw GeofenceLimitExceededException on iOS
  /// for (int i = 0; i < 25; i++) {
  ///   await Locus.addGeofence(Geofence(
  ///     identifier: 'fence_$i',
  ///     latitude: 37.7749 + i * 0.01,
  ///     longitude: -122.4194 + i * 0.01,
  ///     radius: 100,
  ///   ));
  /// }
  ///
  /// // ✅ Better approach - manage geofence lifecycle
  /// if (activeGeofences.length >= 20) {
  ///   await Locus.removeGeofence(oldestGeofenceId);
  /// }
  /// await Locus.addGeofence(newGeofence);
  /// ```
  const GeofenceLimitExceededException(
      {required int limit, required int attempted})
      : super(
          'Cannot add geofence. Maximum limit of $limit geofences reached (attempted: $attempted).',
          suggestion:
              'Remove unused geofences with Locus.removeGeofence(identifier) before adding new ones.',
        );
}

/// Thrown when tracking profiles are used without being configured.
///
/// This exception is raised when attempting to use profile-based tracking methods
/// (such as switching between profiles) without first setting up the profiles.
///
/// Example scenarios:
/// - Calling `Locus.switchToProfile()` before `setTrackingProfiles()`
/// - Using profile names that were never defined
/// - Accessing profile state without initialization
class TrackingProfilesNotConfiguredException extends LocusException {
  /// Creates a [TrackingProfilesNotConfiguredException].
  ///
  /// Thrown when profile-related operations are attempted without profile setup.
  ///
  /// Example:
  /// ```dart
  /// // ❌ This will throw TrackingProfilesNotConfiguredException
  /// await Locus.switchToProfile('driving');
  ///
  /// // ✅ Correct usage
  /// await Locus.setTrackingProfiles({
  ///   'walking': Config.balanced(updateInterval: 5000),
  ///   'driving': Config.reactive(updateInterval: 2000),
  /// });
  /// await Locus.switchToProfile('driving');
  /// ```
  const TrackingProfilesNotConfiguredException()
      : super(
          'Tracking profiles have not been configured.',
          suggestion:
              'Call Locus.setTrackingProfiles() before using profile-related methods.',
        );
}

/// Thrown when a geofence workflow references an invalid geofence.
///
/// This exception occurs when setting up geofence workflows that reference
/// geofences that don't exist or have invalid configurations. Workflows must
/// only reference properly registered geofences.
///
/// Example scenarios:
/// - Workflow references a geofence ID that was never added
/// - Geofence was removed but workflow still references it
/// - Circular dependencies in workflow transitions
class InvalidGeofenceWorkflowException extends LocusException {
  /// Creates an [InvalidGeofenceWorkflowException].
  ///
  /// The [workflowId] identifies the problematic workflow, and [reason]
  /// provides additional context about the validation failure.
  ///
  /// Example:
  /// ```dart
  /// // ❌ This will throw InvalidGeofenceWorkflowException
  /// await Locus.setGeofenceWorkflow(GeofenceWorkflow(
  ///   id: 'home_workflow',
  ///   geofences: ['home', 'office'], // 'office' doesn't exist!
  /// ));
  ///
  /// // ✅ Correct usage
  /// await Locus.addGeofence(homeGeofence);
  /// await Locus.addGeofence(officeGeofence);
  /// await Locus.setGeofenceWorkflow(GeofenceWorkflow(
  ///   id: 'home_workflow',
  ///   geofences: ['home', 'office'],
  /// ));
  /// ```
  const InvalidGeofenceWorkflowException(
      {required String workflowId, String? reason})
      : super(
          'Invalid geofence workflow "$workflowId". ${reason ?? ""}',
          suggestion:
              'Ensure all geofences referenced in the workflow are registered.',
        );
}

/// Thrown when native plugin is not available.
///
/// This exception indicates that the Locus native plugin cannot be accessed.
/// This typically occurs due to installation issues, unsupported platforms,
/// or communication failures between Dart and native code.
///
/// Example scenarios:
/// - Running on an unsupported platform (e.g., web, desktop without support)
/// - Native plugin not properly linked during build
/// - Method channel communication failure
class PluginNotAvailableException extends LocusException {
  /// Creates a [PluginNotAvailableException].
  ///
  /// The optional [platform] parameter specifies which platform is unavailable.
  ///
  /// Example:
  /// ```dart
  /// // This might throw PluginNotAvailableException on web
  /// try {
  ///   await Locus.ready(Config.balanced());
  /// } on PluginNotAvailableException catch (e) {
  ///   print('Locus not supported: $e');
  ///   // Fall back to alternative implementation
  /// }
  /// ```
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
      '[Locus] Sync paused: Received 401 Unauthorized. Call Locus.dataSync.resume() after refreshing your auth token.';

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
