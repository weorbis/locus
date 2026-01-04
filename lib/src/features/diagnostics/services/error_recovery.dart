/// Error recovery API for handling Locus SDK errors gracefully.
///
/// Provides centralized error handling with recovery strategies
/// and automatic retry mechanisms.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:locus/src/models.dart';

/// Configuration for error handling and recovery.
///
/// Example:
/// ```dart
/// Locus.setErrorHandler(ErrorRecoveryConfig(
///   onError: (error, context) {
///     analytics.logError(error);
///     return error.suggestedRecovery ?? RecoveryAction.retry;
///   },
///   maxRetries: 3,
///   retryDelay: Duration(seconds: 5),
///   retryBackoff: 2.0,
/// ));
/// ```
class ErrorRecoveryConfig {
  /// Callback to handle errors and determine recovery action.
  ///
  /// Return [RecoveryAction] to specify how to recover.
  final RecoveryAction Function(LocusError error, ErrorContext context)?
      onError;

  /// Callback when an error is resolved (after successful retry).
  final void Function(LocusError error, int attemptsTaken)? onResolved;

  /// Callback when max retries exhausted.
  final void Function(LocusError error)? onExhausted;

  /// Maximum number of retry attempts.
  final int maxRetries;

  /// Initial delay between retries.
  final Duration retryDelay;

  /// Backoff multiplier for successive retries.
  ///
  /// Each retry delay is multiplied by this factor.
  final double retryBackoff;

  /// Maximum delay between retries.
  final Duration maxRetryDelay;

  /// Whether to automatically restart tracking after certain errors.
  final bool autoRestart;

  /// Error types to automatically retry.
  final Set<LocusErrorType> autoRetryTypes;

  /// Error types to ignore (not propagate to listeners).
  final Set<LocusErrorType> ignoreTypes;

  /// Whether to log errors to the console.
  final bool logErrors;

  /// Creates an error recovery configuration.
  const ErrorRecoveryConfig({
    this.onError,
    this.onResolved,
    this.onExhausted,
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 5),
    this.retryBackoff = 2.0,
    this.maxRetryDelay = const Duration(minutes: 5),
    this.autoRestart = true,
    this.autoRetryTypes = const {
      LocusErrorType.locationTimeout,
      LocusErrorType.networkError,
      LocusErrorType.serviceDisconnected,
    },
    this.ignoreTypes = const {},
    this.logErrors = true,
  });

  /// Default configuration with sensible defaults.
  static const ErrorRecoveryConfig defaults = ErrorRecoveryConfig();

  /// Aggressive retry - more attempts, shorter delays.
  static const ErrorRecoveryConfig aggressive = ErrorRecoveryConfig(
    maxRetries: 5,
    retryDelay: Duration(seconds: 2),
    retryBackoff: 1.5,
    autoRestart: true,
  );

  /// Conservative - fewer retries, longer delays.
  static const ErrorRecoveryConfig conservative = ErrorRecoveryConfig(
    maxRetries: 2,
    retryDelay: Duration(seconds: 30),
    retryBackoff: 2.0,
    autoRestart: false,
  );

  /// Creates a copy with the given fields replaced.
  ErrorRecoveryConfig copyWith({
    RecoveryAction Function(LocusError, ErrorContext)? onError,
    void Function(LocusError, int)? onResolved,
    void Function(LocusError)? onExhausted,
    int? maxRetries,
    Duration? retryDelay,
    double? retryBackoff,
    Duration? maxRetryDelay,
    bool? autoRestart,
    Set<LocusErrorType>? autoRetryTypes,
    Set<LocusErrorType>? ignoreTypes,
    bool? logErrors,
  }) {
    return ErrorRecoveryConfig(
      onError: onError ?? this.onError,
      onResolved: onResolved ?? this.onResolved,
      onExhausted: onExhausted ?? this.onExhausted,
      maxRetries: maxRetries ?? this.maxRetries,
      retryDelay: retryDelay ?? this.retryDelay,
      retryBackoff: retryBackoff ?? this.retryBackoff,
      maxRetryDelay: maxRetryDelay ?? this.maxRetryDelay,
      autoRestart: autoRestart ?? this.autoRestart,
      autoRetryTypes: autoRetryTypes ?? this.autoRetryTypes,
      ignoreTypes: ignoreTypes ?? this.ignoreTypes,
      logErrors: logErrors ?? this.logErrors,
    );
  }

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'maxRetries': maxRetries,
        'retryDelayMs': retryDelay.inMilliseconds,
        'retryBackoff': retryBackoff,
        'maxRetryDelayMs': maxRetryDelay.inMilliseconds,
        'autoRestart': autoRestart,
        'autoRetryTypes': autoRetryTypes.map((e) => e.name).toList(),
        'ignoreTypes': ignoreTypes.map((e) => e.name).toList(),
        'logErrors': logErrors,
      };
}

/// Recovery action to take after an error.
enum RecoveryAction {
  /// Ignore the error and continue.
  ignore,

  /// Retry the failed operation.
  retry,

  /// Restart the entire tracking service.
  restart,

  /// Stop tracking completely.
  stop,

  /// Request user action (e.g., enable permissions).
  requestUserAction,

  /// Fall back to a lower power mode.
  fallbackLowPower,

  /// Propagate the error (default behavior).
  propagate,
}

/// Locus SDK error with classification and recovery hints.
class LocusError implements Exception {
  /// Error type classification.
  final LocusErrorType type;

  /// Human-readable error message.
  final String message;

  /// Original exception if available.
  final Object? originalError;

  /// Stack trace if available.
  final StackTrace? stackTrace;

  /// Operation that failed.
  final String? operation;

  /// Whether this error is recoverable.
  final bool isRecoverable;

  /// Suggested recovery action.
  final RecoveryAction? suggestedRecovery;

  /// Additional error details.
  final JsonMap? details;

  /// Timestamp when error occurred.
  final DateTime timestamp;

  /// Creates a Locus error.
  LocusError({
    required this.type,
    required this.message,
    this.originalError,
    this.stackTrace,
    this.operation,
    this.isRecoverable = true,
    this.suggestedRecovery,
    this.details,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Creates from a generic exception.
  factory LocusError.fromException(Object error, [StackTrace? stack]) {
    if (error is LocusError) return error;

    return LocusError(
      type: LocusErrorType.unknown,
      message: error.toString(),
      originalError: error,
      stackTrace: stack,
    );
  }

  /// Location permission denied.
  factory LocusError.permissionDenied({String? message}) => LocusError(
        type: LocusErrorType.permissionDenied,
        message: message ?? 'Location permission denied',
        isRecoverable: true,
        suggestedRecovery: RecoveryAction.requestUserAction,
      );

  /// Location services disabled.
  factory LocusError.servicesDisabled({String? message}) => LocusError(
        type: LocusErrorType.servicesDisabled,
        message: message ?? 'Location services are disabled',
        isRecoverable: true,
        suggestedRecovery: RecoveryAction.requestUserAction,
      );

  /// Location acquisition timeout.
  factory LocusError.timeout({Duration? timeout}) => LocusError(
        type: LocusErrorType.locationTimeout,
        message: 'Location request timed out',
        isRecoverable: true,
        suggestedRecovery: RecoveryAction.retry,
        details: timeout != null ? {'timeoutMs': timeout.inMilliseconds} : null,
      );

  /// Network error during sync.
  factory LocusError.networkError({String? message, Object? originalError}) =>
      LocusError(
        type: LocusErrorType.networkError,
        message: message ?? 'Network error during sync',
        originalError: originalError,
        isRecoverable: true,
        suggestedRecovery: RecoveryAction.retry,
      );

  /// Service disconnected.
  factory LocusError.serviceDisconnected() => LocusError(
        type: LocusErrorType.serviceDisconnected,
        message: 'Background service disconnected',
        isRecoverable: true,
        suggestedRecovery: RecoveryAction.restart,
      );

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'type': type.name,
        'message': message,
        if (operation != null) 'operation': operation,
        'isRecoverable': isRecoverable,
        if (suggestedRecovery != null)
          'suggestedRecovery': suggestedRecovery!.name,
        if (details != null) 'details': details,
        'timestamp': timestamp.toIso8601String(),
      };

  @override
  String toString() => 'LocusError(${type.name}): $message';
}

/// Classification of Locus errors.
enum LocusErrorType {
  /// Location permission was denied.
  permissionDenied,

  /// Location services are disabled.
  servicesDisabled,

  /// Location request timed out.
  locationTimeout,

  /// Network error during HTTP sync.
  networkError,

  /// Background service disconnected.
  serviceDisconnected,

  /// Configuration error.
  configError,

  /// Geofence operation failed.
  geofenceError,

  /// Trip tracking error.
  tripError,

  /// Plugin/platform error.
  platformError,

  /// SDK initialization error.
  initializationError,

  /// Authorization changed unexpectedly.
  authorizationChanged,

  /// Unknown error.
  unknown,
}

/// Context about the error for decision making.
class ErrorContext {
  /// Number of times this error has been retried.
  final int retryCount;

  /// Time since first occurrence of this error.
  final Duration? timeSinceFirstOccurrence;

  /// Whether tracking is currently active.
  final bool isTrackingActive;

  /// Current battery level if available.
  final int? batteryLevel;

  /// Whether device is charging.
  final bool? isCharging;

  /// Whether network is available.
  final bool? networkAvailable;

  /// Creates an error context.
  const ErrorContext({
    this.retryCount = 0,
    this.timeSinceFirstOccurrence,
    this.isTrackingActive = false,
    this.batteryLevel,
    this.isCharging,
    this.networkAvailable,
  });
}

/// Manages error recovery for the Locus SDK.
class ErrorRecoveryManager {
  ErrorRecoveryConfig _config;
  final Map<LocusErrorType, int> _retryCounts = {};
  final Map<LocusErrorType, DateTime> _firstOccurrences = {};
  final _errorController = StreamController<LocusError>.broadcast();
  final Map<LocusErrorType, Timer> _retryTimers = {};

  /// Creates an error recovery manager.
  ErrorRecoveryManager([ErrorRecoveryConfig? config])
      : _config = config ?? const ErrorRecoveryConfig();

  /// Stream of errors for external observation.
  Stream<LocusError> get errors => _errorController.stream;

  /// Updates the configuration.
  void configure(ErrorRecoveryConfig config) {
    _config = config;
  }

  /// Handles an error and determines recovery action.
  ///
  /// Returns the recovery action to take.
  Future<RecoveryAction> handleError(
    LocusError error, {
    bool isTrackingActive = false,
    int? batteryLevel,
    bool? isCharging,
    bool? networkAvailable,
  }) async {
    // Check if we should ignore this error type
    if (_config.ignoreTypes.contains(error.type)) {
      return RecoveryAction.ignore;
    }

    // Track retry counts
    final retryCount = _retryCounts[error.type] ?? 0;
    _retryCounts[error.type] = retryCount + 1;

    // Track first occurrence
    _firstOccurrences[error.type] ??= DateTime.now();
    final timeSinceFirst =
        DateTime.now().difference(_firstOccurrences[error.type]!);

    // Build context
    final context = ErrorContext(
      retryCount: retryCount,
      timeSinceFirstOccurrence: timeSinceFirst,
      isTrackingActive: isTrackingActive,
      batteryLevel: batteryLevel,
      isCharging: isCharging,
      networkAvailable: networkAvailable,
    );

    // Log if configured
    if (_config.logErrors) {
      debugPrint('[Locus] Error: ${error.type.name} - ${error.message} '
          '(attempt ${retryCount + 1}/${_config.maxRetries})');
    }

    // Let user decide
    RecoveryAction action;
    if (_config.onError != null) {
      action = _config.onError!(error, context);
    } else {
      action = _determineRecoveryAction(error, context);
    }

    // Emit error
    _errorController.add(error);

    return action;
  }

  /// Determines the recovery action based on error type and config.
  RecoveryAction _determineRecoveryAction(
    LocusError error,
    ErrorContext context,
  ) {
    // Check if we've exhausted retries
    if (context.retryCount >= _config.maxRetries) {
      _config.onExhausted?.call(error);
      _retryCounts.remove(error.type);
      _firstOccurrences.remove(error.type);
      _retryTimers[error.type]?.cancel();
      _retryTimers.remove(error.type);

      // Fall back to lower power mode on persistent errors
      if (error.isRecoverable) {
        return RecoveryAction.fallbackLowPower;
      }
      return RecoveryAction.propagate;
    }

    // Auto-retry certain error types
    if (_config.autoRetryTypes.contains(error.type)) {
      return RecoveryAction.retry;
    }

    // Use suggested recovery if available
    if (error.suggestedRecovery != null) {
      return error.suggestedRecovery!;
    }

    // Default based on recoverability
    return error.isRecoverable
        ? RecoveryAction.retry
        : RecoveryAction.propagate;
  }

  /// Calculates delay for next retry attempt.
  Duration getRetryDelay(LocusErrorType errorType) {
    final retryCount = _retryCounts[errorType] ?? 0;
    var delay = _config.retryDelay;

    // Apply exponential backoff
    for (var i = 0; i < retryCount; i++) {
      delay = Duration(
        milliseconds: (delay.inMilliseconds * _config.retryBackoff).round(),
      );
    }

    // Cap at max delay
    if (delay > _config.maxRetryDelay) {
      delay = _config.maxRetryDelay;
    }

    return delay;
  }

  /// Schedules a retry with appropriate delay.
  void scheduleRetry(
    LocusErrorType errorType,
    void Function() retryAction,
  ) {
    final delay = getRetryDelay(errorType);
    _retryTimers[errorType]?.cancel();
    _retryTimers[errorType] = Timer(delay, () {
      _retryTimers.remove(errorType);
      retryAction();
    });
  }

  /// Marks an error as resolved (e.g., after successful retry).
  void markResolved(LocusErrorType errorType) {
    final attempts = _retryCounts[errorType] ?? 1;
    _config.onResolved?.call(
      LocusError(type: errorType, message: 'Resolved after retry'),
      attempts,
    );
    _retryCounts.remove(errorType);
    _firstOccurrences.remove(errorType);
    _retryTimers[errorType]?.cancel();
    _retryTimers.remove(errorType);
  }

  /// Clears all error state.
  void reset() {
    _retryCounts.clear();
    _firstOccurrences.clear();
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
  }

  /// Disposes resources.
  void dispose() {
    reset();
    _errorController.close();
  }
}
