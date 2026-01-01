/// Significant location change monitoring for ultra-low power tracking.
///
/// Uses OS-level significant location change APIs to monitor large
/// movements (~500m) with minimal battery impact.
library;

import 'dart:async';
import 'package:locus/src/config/constants.dart';
import 'package:locus/src/models/models.dart';
import 'package:locus/src/utils/location_utils.dart';

/// Configuration for significant location change monitoring.
///
/// This mode uses the OS's most battery-efficient location monitoring:
/// - iOS: `startMonitoringSignificantLocationChanges()` - uses cell/WiFi
/// - Android: Emulated with large radius geofence auto-follow
///
/// Example:
/// ```dart
/// await Locus.startSignificantChangeMonitoring(
///   SignificantChangeConfig(
///     minDisplacementMeters: 500,
///     deferUntilMoved: true,
///     onSignificantChange: (location) {
///       print('Significant move: ${location.coords.latitude}');
///     },
///   ),
/// );
/// ```
class SignificantChangeConfig {
  /// Minimum displacement in meters to trigger an update.
  ///
  /// Default is 500m which is the iOS standard.
  /// Smaller values may increase battery usage.
  final double minDisplacementMeters;

  /// Whether to defer updates until the device has actually moved.
  ///
  /// When true, the first update is deferred until movement is detected.
  final bool deferUntilMoved;

  /// Callback when a significant location change is detected.
  final void Function(Location location)? onSignificantChange;

  /// Whether to wake the app from background/terminated state.
  final bool wakeFromBackground;

  /// Whether to also monitor when app is in foreground.
  ///
  /// Set to false to only use significant changes in background,
  /// and normal tracking in foreground.
  final bool monitorInForeground;

  /// Maximum interval between updates regardless of movement.
  ///
  /// If set, will force a location update after this duration
  /// even if no significant movement detected.
  final Duration? maxUpdateInterval;

  /// Creates a significant change configuration.
  const SignificantChangeConfig({
    this.minDisplacementMeters = 500,
    this.deferUntilMoved = true,
    this.onSignificantChange,
    this.wakeFromBackground = true,
    this.monitorInForeground = false,
    this.maxUpdateInterval,
  });

  /// Default configuration matching iOS behavior.
  static const SignificantChangeConfig defaults = SignificantChangeConfig();

  /// More sensitive - shorter distance threshold.
  static const SignificantChangeConfig sensitive = SignificantChangeConfig(
    minDisplacementMeters: 250,
    maxUpdateInterval: Duration(minutes: 30),
  );

  /// Maximum battery savings - larger threshold.
  static const SignificantChangeConfig ultraLowPower = SignificantChangeConfig(
    minDisplacementMeters: kDefaultSignificantChangeDisplacementMeters,
    deferUntilMoved: true,
    maxUpdateInterval: Duration(hours: 1),
  );

  /// Creates a copy with the given fields replaced.
  SignificantChangeConfig copyWith({
    double? minDisplacementMeters,
    bool? deferUntilMoved,
    void Function(Location)? onSignificantChange,
    bool? wakeFromBackground,
    bool? monitorInForeground,
    Duration? maxUpdateInterval,
  }) {
    return SignificantChangeConfig(
      minDisplacementMeters:
          minDisplacementMeters ?? this.minDisplacementMeters,
      deferUntilMoved: deferUntilMoved ?? this.deferUntilMoved,
      onSignificantChange: onSignificantChange ?? this.onSignificantChange,
      wakeFromBackground: wakeFromBackground ?? this.wakeFromBackground,
      monitorInForeground: monitorInForeground ?? this.monitorInForeground,
      maxUpdateInterval: maxUpdateInterval ?? this.maxUpdateInterval,
    );
  }

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'minDisplacementMeters': minDisplacementMeters,
        'deferUntilMoved': deferUntilMoved,
        'wakeFromBackground': wakeFromBackground,
        'monitorInForeground': monitorInForeground,
        if (maxUpdateInterval != null)
          'maxUpdateIntervalMs': maxUpdateInterval!.inMilliseconds,
      };

  /// Creates from a map.
  factory SignificantChangeConfig.fromMap(JsonMap map) {
    return SignificantChangeConfig(
      minDisplacementMeters:
          (map['minDisplacementMeters'] as num?)?.toDouble() ?? 500,
      deferUntilMoved: map['deferUntilMoved'] as bool? ?? true,
      wakeFromBackground: map['wakeFromBackground'] as bool? ?? true,
      monitorInForeground: map['monitorInForeground'] as bool? ?? false,
      maxUpdateInterval: map['maxUpdateIntervalMs'] != null
          ? Duration(milliseconds: (map['maxUpdateIntervalMs'] as num).toInt())
          : null,
    );
  }
}

/// Event emitted when a significant location change is detected.
class SignificantChangeEvent {
  /// The new location after the significant change.
  final Location location;

  /// Previous location for reference.
  final Location? previousLocation;

  /// Estimated displacement in meters.
  final double? displacementMeters;

  /// Time since last significant change.
  final Duration? timeSinceLastChange;

  /// Whether this was triggered by the max interval timer.
  final bool wasTimerTriggered;

  /// Creates a significant change event.
  SignificantChangeEvent({
    required this.location,
    this.previousLocation,
    this.displacementMeters,
    this.timeSinceLastChange,
    this.wasTimerTriggered = false,
  });

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'location': location.toMap(),
        if (previousLocation != null)
          'previousLocation': previousLocation!.toMap(),
        if (displacementMeters != null)
          'displacementMeters': displacementMeters,
        if (timeSinceLastChange != null)
          'timeSinceLastChangeMs': timeSinceLastChange!.inMilliseconds,
        'wasTimerTriggered': wasTimerTriggered,
      };
}

/// Manager for significant location change monitoring.
///
/// This provides a Dart-side abstraction over the native significant
/// location change APIs, with fallback emulation on Android.
class SignificantChangeManager {
  SignificantChangeConfig? _config;
  Location? _lastLocation;
  DateTime? _lastChangeTime;
  Timer? _maxIntervalTimer;
  final _controller = StreamController<SignificantChangeEvent>.broadcast();
  bool _isMonitoring = false;

  /// Whether monitoring is currently active.
  bool get isMonitoring => _isMonitoring;

  /// Stream of significant change events.
  Stream<SignificantChangeEvent> get events => _controller.stream;

  /// Current configuration.
  SignificantChangeConfig? get config => _config;

  /// Starts significant location change monitoring.
  void start(SignificantChangeConfig config) {
    if (_isMonitoring) {
      stop();
    }

    _config = config;
    _isMonitoring = true;
    _lastChangeTime = DateTime.now();

    // Start max interval timer if configured
    if (config.maxUpdateInterval != null) {
      _maxIntervalTimer = Timer.periodic(
        config.maxUpdateInterval!,
        (_) => _onMaxIntervalReached(),
      );
    }
  }

  /// Stops monitoring.
  void stop() {
    _isMonitoring = false;
    _maxIntervalTimer?.cancel();
    _maxIntervalTimer = null;
  }

  /// Processes a location update.
  ///
  /// Call this with each location to check if it represents
  /// a significant change.
  void processLocation(Location location) {
    if (!_isMonitoring || _config == null) return;

    // First location - store and potentially emit
    if (_lastLocation == null) {
      _lastLocation = location;
      if (!_config!.deferUntilMoved) {
        _emitChange(location, wasTimerTriggered: false);
      }
      return;
    }

    // Calculate displacement
    final displacement = LocationUtils.calculateDistance(
      _lastLocation!.coords,
      location.coords,
    );

    // Check if significant
    if (displacement >= _config!.minDisplacementMeters) {
      _emitChange(
        location,
        displacement: displacement,
        wasTimerTriggered: false,
      );
      _lastLocation = location;
    }
  }

  void _onMaxIntervalReached() {
    if (_lastLocation == null || !_isMonitoring) return;

    // Emit the last known location as a timer-triggered update
    _emitChange(
      _lastLocation!,
      wasTimerTriggered: true,
    );
  }

  void _emitChange(
    Location location, {
    double? displacement,
    required bool wasTimerTriggered,
  }) {
    final timeSinceLastChange = _lastChangeTime != null
        ? DateTime.now().difference(_lastChangeTime!)
        : null;

    final event = SignificantChangeEvent(
      location: location,
      previousLocation: _lastLocation,
      displacementMeters: displacement,
      timeSinceLastChange: timeSinceLastChange,
      wasTimerTriggered: wasTimerTriggered,
    );

    _lastChangeTime = DateTime.now();
    _controller.add(event);
    _config?.onSignificantChange?.call(location);
  }

  /// Calculates distance between two coordinates in meters using Haversine formula.

  /// Disposes resources.
  void dispose() {
    stop();
    _controller.close();
  }
}
