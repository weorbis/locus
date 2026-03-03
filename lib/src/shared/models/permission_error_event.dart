import 'package:locus/src/shared/models/json_map.dart';

/// Represents a permission-related error emitted through the event stream.
///
/// This event is emitted when the native side detects a permission issue,
/// such as a missing manifest declaration or a denied runtime permission,
/// and can be handled gracefully without crashing the stream.
class PermissionErrorEvent {
  const PermissionErrorEvent({
    required this.code,
    required this.message,
    this.permissions = const [],
  });

  factory PermissionErrorEvent.fromMap(JsonMap map) {
    return PermissionErrorEvent(
      code: map['code'] as String? ?? 'UNKNOWN',
      message: map['message'] as String? ?? '',
      permissions: (map['permissions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  /// Error code identifying the type of permission error.
  ///
  /// Known codes:
  /// - `ERR_MISSING_MANIFEST` — permission not declared in AndroidManifest.xml
  /// - `ERR_PERMISSION_DENIED` — user has not granted the runtime permission
  final String code;

  /// Human-readable description of the error.
  final String message;

  /// List of affected permission identifiers (e.g., `android.permission.ACCESS_FINE_LOCATION`).
  final List<String> permissions;

  JsonMap toMap() => {
        'code': code,
        'message': message,
        if (permissions.isNotEmpty) 'permissions': permissions,
      };
}
