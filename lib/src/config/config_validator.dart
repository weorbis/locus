/// Configuration validator for Locus SDK.
///
/// Validates [Config] objects and provides clear, actionable error messages
/// when configurations are invalid or suboptimal.
library;

import 'package:locus/src/config/geolocation_config.dart';

/// Result of a configuration validation.
class ConfigValidationResult {
  /// Whether the configuration is valid.
  final bool isValid;

  /// List of validation errors (if any).
  final List<ConfigValidationError> errors;

  /// List of validation warnings (if any).
  final List<ConfigValidationWarning> warnings;

  const ConfigValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });

  /// Creates a successful validation result.
  const ConfigValidationResult.success({this.warnings = const []})
      : isValid = true,
        errors = const [];

  /// Creates a failed validation result.
  const ConfigValidationResult.failure(this.errors, {this.warnings = const []})
      : isValid = false;

  @override
  String toString() {
    if (isValid && warnings.isEmpty) {
      return 'ConfigValidationResult: Valid';
    }
    final buffer = StringBuffer('ConfigValidationResult:\n');
    if (errors.isNotEmpty) {
      buffer.writeln('  Errors:');
      for (final error in errors) {
        buffer.writeln('    - ${error.message}');
      }
    }
    if (warnings.isNotEmpty) {
      buffer.writeln('  Warnings:');
      for (final warning in warnings) {
        buffer.writeln('    - ${warning.message}');
      }
    }
    return buffer.toString();
  }
}

/// A configuration validation error.
class ConfigValidationError {
  /// The configuration field that is invalid.
  final String field;

  /// Human-readable error message.
  final String message;

  /// Suggestion on how to fix the error.
  final String? suggestion;

  /// Example of valid configuration.
  final String? example;

  const ConfigValidationError({
    required this.field,
    required this.message,
    this.suggestion,
    this.example,
  });

  @override
  String toString() {
    final buffer = StringBuffer('$field: $message');
    if (suggestion != null) {
      buffer.write('\n  Suggestion: $suggestion');
    }
    if (example != null) {
      buffer.write('\n  Example: $example');
    }
    return buffer.toString();
  }
}

/// A configuration validation warning.
class ConfigValidationWarning {
  /// The configuration field with a potential issue.
  final String field;

  /// Human-readable warning message.
  final String message;

  /// Suggestion on how to improve.
  final String? suggestion;

  const ConfigValidationWarning({
    required this.field,
    required this.message,
    this.suggestion,
  });

  @override
  String toString() {
    final buffer = StringBuffer('$field: $message');
    if (suggestion != null) {
      buffer.write(' ($suggestion)');
    }
    return buffer.toString();
  }
}

/// Validates [Config] objects for the Locus SDK.
class ConfigValidator {
  const ConfigValidator._();

  /// Validates a configuration and returns detailed results.
  ///
  /// Example:
  /// ```dart
  /// final result = ConfigValidator.validate(config);
  /// if (!result.isValid) {
  ///   for (final error in result.errors) {
  ///     print('Error: ${error.message}');
  ///     if (error.suggestion != null) {
  ///       print('  Fix: ${error.suggestion}');
  ///     }
  ///   }
  /// }
  /// ```
  static ConfigValidationResult validate(Config config) {
    final errors = <ConfigValidationError>[];
    final warnings = <ConfigValidationWarning>[];

    // Validate distance filter
    if (config.distanceFilter != null && config.distanceFilter! < 0) {
      errors.add(const ConfigValidationError(
        field: 'distanceFilter',
        message: 'Distance filter cannot be negative',
        suggestion:
            'Use a positive value (e.g., 10 meters) or null for default',
        example: 'Config(distanceFilter: 10)',
      ));
    }

    if (config.distanceFilter != null && config.distanceFilter! < 5) {
      warnings.add(const ConfigValidationWarning(
        field: 'distanceFilter',
        message: 'Very small distance filter will increase battery usage',
        suggestion: 'Consider using at least 10 meters for better battery life',
      ));
    }

    // Validate stationary radius
    if (config.stationaryRadius != null && config.stationaryRadius! < 0) {
      errors.add(const ConfigValidationError(
        field: 'stationaryRadius',
        message: 'Stationary radius cannot be negative',
        suggestion: 'Use a positive value (e.g., 25 meters)',
        example: 'Config(stationaryRadius: 25)',
      ));
    }

    // Validate stop timeout
    if (config.stopTimeout != null && config.stopTimeout! < 0) {
      errors.add(const ConfigValidationError(
        field: 'stopTimeout',
        message: 'Stop timeout cannot be negative',
        suggestion: 'Use a positive value in minutes (e.g., 5)',
        example: 'Config(stopTimeout: 5)',
      ));
    }

    // Validate activity recognition interval
    if (config.activityRecognitionInterval != null) {
      if (config.activityRecognitionInterval! < 0) {
        errors.add(const ConfigValidationError(
          field: 'activityRecognitionInterval',
          message: 'Activity recognition interval cannot be negative',
          suggestion: 'Use a positive value in milliseconds (e.g., 10000)',
          example: 'Config(activityRecognitionInterval: 10000)',
        ));
      } else if (config.activityRecognitionInterval! < 1000) {
        warnings.add(const ConfigValidationWarning(
          field: 'activityRecognitionInterval',
          message: 'Very frequent activity updates will increase battery usage',
          suggestion: 'Consider using at least 5000ms (5 seconds)',
        ));
      }
    }

    // Validate heartbeat interval
    if (config.heartbeatInterval != null) {
      if (config.heartbeatInterval! < 0) {
        errors.add(const ConfigValidationError(
          field: 'heartbeatInterval',
          message: 'Heartbeat interval cannot be negative',
          suggestion: 'Use a positive value in seconds (e.g., 60)',
          example: 'Config(heartbeatInterval: 60)',
        ));
      } else if (config.heartbeatInterval! > 0 &&
          config.heartbeatInterval! < 30) {
        warnings.add(const ConfigValidationWarning(
          field: 'heartbeatInterval',
          message: 'Very frequent heartbeats may drain battery quickly',
          suggestion: 'Consider using at least 60 seconds',
        ));
      }
    }

    // Validate HTTP configuration
    if (config.url != null && config.url!.isNotEmpty) {
      if (!config.url!.startsWith('http://') &&
          !config.url!.startsWith('https://')) {
        errors.add(ConfigValidationError(
          field: 'url',
          message: 'URL must start with http:// or https://',
          suggestion: 'Add the protocol prefix to your URL',
          example: 'Config(url: "https://api.example.com/locations")',
        ));
      }

      if (config.url!.startsWith('http://')) {
        warnings.add(const ConfigValidationWarning(
          field: 'url',
          message: 'Using HTTP instead of HTTPS is insecure',
          suggestion: 'Use HTTPS for production apps',
        ));
      }
    }

    // Validate sync when URL is configured
    if (config.autoSync == true &&
        (config.url == null || config.url!.isEmpty)) {
      errors.add(const ConfigValidationError(
        field: 'autoSync',
        message: 'autoSync is enabled but no URL is configured',
        suggestion: 'Either set a URL or disable autoSync',
        example:
            'Config(url: "https://api.example.com/locations", autoSync: true)',
      ));
    }

    // Validate retry configuration
    if (config.maxRetry != null && config.maxRetry! < 0) {
      errors.add(const ConfigValidationError(
        field: 'maxRetry',
        message: 'maxRetry cannot be negative',
        suggestion: 'Use 0 to disable retries or a positive value',
        example: 'Config(maxRetry: 3)',
      ));
    }

    if (config.retryDelay != null && config.retryDelay! < 0) {
      errors.add(const ConfigValidationError(
        field: 'retryDelay',
        message: 'retryDelay cannot be negative',
        suggestion: 'Use a positive value in milliseconds',
        example: 'Config(retryDelay: 5000)',
      ));
    }

    // Validate batch configuration
    if (config.batchSync == true && config.maxBatchSize != null) {
      if (config.maxBatchSize! < 1) {
        errors.add(const ConfigValidationError(
          field: 'maxBatchSize',
          message: 'maxBatchSize must be at least 1 when batchSync is enabled',
          suggestion: 'Use a positive value',
          example: 'Config(batchSync: true, maxBatchSize: 50)',
        ));
      } else if (config.maxBatchSize! > 500) {
        warnings.add(const ConfigValidationWarning(
          field: 'maxBatchSize',
          message: 'Very large batch sizes may cause memory issues',
          suggestion: 'Consider using 50-100 for optimal performance',
        ));
      }
    }

    // Validate schedule format
    if (config.schedule != null && config.schedule!.isNotEmpty) {
      final schedulePattern = RegExp(r'^\d{2}:\d{2}-\d{2}:\d{2}$');
      for (final window in config.schedule!) {
        if (!schedulePattern.hasMatch(window)) {
          errors.add(ConfigValidationError(
            field: 'schedule',
            message: 'Invalid schedule format: "$window"',
            suggestion: 'Use HH:mm-HH:mm format (24-hour)',
            example: 'Config(schedule: ["08:00-12:00", "13:00-18:00"])',
          ));
        }
      }
    }

    // Validate log configuration
    if (config.logMaxDays != null && config.logMaxDays! < 0) {
      errors.add(const ConfigValidationError(
        field: 'logMaxDays',
        message: 'logMaxDays cannot be negative',
        suggestion: 'Use 0 to disable log retention or a positive value',
        example: 'Config(logMaxDays: 7)',
      ));
    }

    // Validate persist configuration
    if (config.maxDaysToPersist != null && config.maxDaysToPersist! < 0) {
      errors.add(const ConfigValidationError(
        field: 'maxDaysToPersist',
        message: 'maxDaysToPersist cannot be negative',
        suggestion: 'Use 0 to disable or a positive value',
        example: 'Config(maxDaysToPersist: 7)',
      ));
    }

    if (config.maxRecordsToPersist != null && config.maxRecordsToPersist! < 0) {
      errors.add(const ConfigValidationError(
        field: 'maxRecordsToPersist',
        message: 'maxRecordsToPersist cannot be negative',
        suggestion: 'Use 0 to disable or a positive value',
        example: 'Config(maxRecordsToPersist: 1000)',
      ));
    }

    // Validate geofence configuration
    if (config.maxMonitoredGeofences != null &&
        config.maxMonitoredGeofences! < 0) {
      errors.add(const ConfigValidationError(
        field: 'maxMonitoredGeofences',
        message: 'maxMonitoredGeofences cannot be negative',
        suggestion: 'Use 0 for unlimited or a positive value',
        example: 'Config(maxMonitoredGeofences: 20)',
      ));
    }

    // Check for conflicting options
    if (config.stopOnTerminate == true && config.enableHeadless == true) {
      warnings.add(const ConfigValidationWarning(
        field: 'stopOnTerminate',
        message: 'stopOnTerminate=true with enableHeadless=true is unusual',
        suggestion: 'If using headless mode, consider stopOnTerminate: false',
      ));
    }

    if (config.startOnBoot == true && config.enableHeadless != true) {
      warnings.add(const ConfigValidationWarning(
        field: 'startOnBoot',
        message: 'startOnBoot requires enableHeadless to function properly',
        suggestion: 'Set enableHeadless: true when using startOnBoot',
      ));
    }

    // Validate HTTP method if provided
    if (config.method != null) {
      final validMethods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];
      final method = config.method!.toUpperCase();
      if (!validMethods.contains(method)) {
        errors.add(ConfigValidationError(
          field: 'method',
          message: 'Invalid HTTP method: ${config.method}',
          suggestion: 'Use one of: ${validMethods.join(", ")}',
          example: 'Config(method: "POST")',
        ));
      }
    }

    // Note: desiredAccuracy is already type-safe as DesiredAccuracy enum
    // No runtime validation needed - compiler ensures valid values

    // Note: triggerActivities is List<ActivityType>? - already type-safe
    // Compiler ensures only valid ActivityType values can be added

    // Validate batchSync with autoSync
    if (config.batchSync == true && config.autoSync != true) {
      warnings.add(const ConfigValidationWarning(
        field: 'batchSync',
        message: 'batchSync=true has no effect when autoSync is disabled',
        suggestion: 'Set autoSync: true to enable automatic syncing',
      ));
    }

    // Validate iOS-specific geofence limits
    if (config.maxMonitoredGeofences != null &&
        config.maxMonitoredGeofences! > 20) {
      warnings.add(const ConfigValidationWarning(
        field: 'maxMonitoredGeofences',
        message: 'iOS has a limit of 20 monitored geofences',
        suggestion:
            'Consider using 20 or fewer for cross-platform compatibility',
      ));
    }

    // Validate speedJumpFilter
    if (config.speedJumpFilter != null && config.speedJumpFilter! < 0) {
      errors.add(const ConfigValidationError(
        field: 'speedJumpFilter',
        message: 'speedJumpFilter cannot be negative',
        suggestion: 'Use a positive value in m/s',
        example: 'Config(speedJumpFilter: 100)',
      ));
    }

    // Validate URL if autoSync is enabled
    if (config.autoSync == true &&
        (config.url == null || config.url!.isEmpty)) {
      warnings.add(const ConfigValidationWarning(
        field: 'url',
        message: 'autoSync is enabled but no URL is configured',
        suggestion: 'Set a url for sync destination or disable autoSync',
      ));
    }

    // Validate httpTimeout
    if (config.httpTimeout != null && config.httpTimeout! < 0) {
      errors.add(const ConfigValidationError(
        field: 'httpTimeout',
        message: 'httpTimeout cannot be negative',
        suggestion: 'Use a positive value in milliseconds',
        example: 'Config(httpTimeout: 30000)',
      ));
    }

    // Validate locationTimeout
    if (config.locationTimeout != null && config.locationTimeout! < 0) {
      errors.add(const ConfigValidationError(
        field: 'locationTimeout',
        message: 'locationTimeout cannot be negative',
        suggestion: 'Use a positive value in seconds',
        example: 'Config(locationTimeout: 30)',
      ));
    }

    // Warn about extras without httpRootProperty
    if (config.extras != null &&
        config.extras!.isNotEmpty &&
        (config.httpRootProperty == null || config.httpRootProperty!.isEmpty)) {
      warnings.add(const ConfigValidationWarning(
        field: 'extras',
        message:
            'extras is configured without httpRootProperty. Locations will be under "locations" key.',
        suggestion:
            'Set httpRootProperty to customize the key (e.g., httpRootProperty: "polygons")',
      ));
    }

    // Warn about autoSync without batchSync
    if (config.autoSync == true && config.batchSync != true) {
      warnings.add(const ConfigValidationWarning(
        field: 'autoSync',
        message:
            'autoSync=true with batchSync=false causes immediate HTTP request per location',
        suggestion:
            'Consider batchSync: true with autoSyncThreshold for efficiency',
      ));
    }

    // Warn about enableHeadless without stopOnTerminate false
    if (config.enableHeadless == true && config.stopOnTerminate != false) {
      warnings.add(const ConfigValidationWarning(
        field: 'enableHeadless',
        message:
            'enableHeadless=true typically requires stopOnTerminate: false',
        suggestion:
            'Set stopOnTerminate: false if you want background tracking to persist',
      ));
    }

    // Return result
    if (errors.isEmpty) {
      return ConfigValidationResult.success(warnings: warnings);
    }
    return ConfigValidationResult.failure(errors, warnings: warnings);
  }

  /// Validates a configuration and throws if invalid.
  ///
  /// Use this when you want to fail fast on invalid configurations.
  ///
  /// Example:
  /// ```dart
  /// try {
  ///   ConfigValidator.assertValid(config);
  /// } on ConfigValidationException catch (e) {
  ///   print('Invalid config: $e');
  /// }
  /// ```
  static void assertValid(Config config) {
    final result = validate(config);
    if (!result.isValid) {
      throw ConfigValidationException(result.errors);
    }
  }
}

/// Exception thrown when configuration validation fails.
class ConfigValidationException implements Exception {
  /// The validation errors that caused this exception.
  final List<ConfigValidationError> errors;

  const ConfigValidationException(this.errors);

  @override
  String toString() {
    final buffer = StringBuffer('ConfigValidationException:\n');
    for (final error in errors) {
      buffer.writeln('  • ${error.field}: ${error.message}');
      if (error.suggestion != null) {
        buffer.writeln('    Fix: ${error.suggestion}');
      }
    }
    return buffer.toString();
  }
}
