/// Enhanced spoof detection with multi-factor analysis.
///
/// Provides configurable detection of mock locations and GPS spoofing
/// attempts using multiple detection vectors.
library;

import 'package:locus/src/config/constants.dart';
import 'package:locus/src/models.dart';
import 'package:locus/src/shared/location_utils.dart';

/// Configuration for spoof detection behavior.
///
/// Multiple detection factors can be combined for more reliable detection:
/// - Mock provider detection (Android)
/// - Impossible speed detection
/// - Altitude anomalies
/// - Accuracy patterns
/// - Location provider analysis
///
/// Example:
/// ```dart
/// final config = SpoofDetectionConfig(
///   enabled: true,
///   blockMockLocations: true,
///   sensitivity: SpoofSensitivity.high,
///   onSpoofDetected: (event) {
///     logSecurityEvent('Potential spoof: ${event.factors}');
///   },
/// );
/// await Locus.setSpoofDetection(config);
/// ```
class SpoofDetectionConfig {
  /// Whether spoof detection is enabled.
  final bool enabled;

  /// Whether to completely block mock/spoofed locations.
  ///
  /// When true, locations flagged as spoofed won't be emitted to listeners.
  /// When false, locations are still emitted but flagged.
  final bool blockMockLocations;

  /// Detection sensitivity level.
  final SpoofSensitivity sensitivity;

  /// Maximum physically possible speed in km/h.
  ///
  /// Speeds above this are considered impossible unless in an aircraft.
  final double maxPossibleSpeedKph;

  /// Maximum allowed altitude change in meters per second.
  ///
  /// Rapid altitude changes can indicate spoofing.
  final double maxAltitudeChangePerSecond;

  /// Minimum number of detection factors required to flag as spoofed.
  ///
  /// Higher values reduce false positives but may miss some spoofing.
  final int minFactorsForDetection;

  /// Callback when spoofing is detected.
  final void Function(SpoofDetectionEvent event)? onSpoofDetected;

  /// Whether to check for mock provider flag (Android only).
  final bool checkMockProvider;

  /// Whether to check for developer options enabled.
  final bool checkDeveloperOptions;

  /// Whether to check for location services running in mock mode.
  final bool checkMockMode;

  /// List of trusted app signatures for mock location allowlisting.
  ///
  /// Apps with these signatures won't trigger mock provider detection.
  /// Useful for allowing specific approved testing apps.
  final List<String> trustedMockProviders;

  /// Creates spoof detection configuration.
  const SpoofDetectionConfig({
    this.enabled = true,
    this.blockMockLocations = false,
    this.sensitivity = SpoofSensitivity.balanced,
    this.maxPossibleSpeedKph = kMaxPossibleSpeedKph,
    this.maxAltitudeChangePerSecond = kMaxAltitudeChangePerSecondMeters,
    this.minFactorsForDetection = kDefaultMinSpoofFactors,
    this.onSpoofDetected,
    this.checkMockProvider = true,
    this.checkDeveloperOptions = false,
    this.checkMockMode = true,
    this.trustedMockProviders = const [],
  });

  /// Disabled detection.
  static const SpoofDetectionConfig disabled = SpoofDetectionConfig(
    enabled: false,
  );

  /// Low sensitivity - fewer false positives.
  static const SpoofDetectionConfig low = SpoofDetectionConfig(
    enabled: true,
    sensitivity: SpoofSensitivity.low,
    minFactorsForDetection: 3,
    blockMockLocations: false,
  );

  /// Balanced detection (default).
  static const SpoofDetectionConfig balanced = SpoofDetectionConfig(
    enabled: true,
    sensitivity: SpoofSensitivity.balanced,
    minFactorsForDetection: 2,
    blockMockLocations: false,
  );

  /// High sensitivity - more aggressive detection.
  static const SpoofDetectionConfig high = SpoofDetectionConfig(
    enabled: true,
    sensitivity: SpoofSensitivity.high,
    minFactorsForDetection: 1,
    blockMockLocations: true,
  );

  /// Financial/security grade - strictest detection.
  static const SpoofDetectionConfig strict = SpoofDetectionConfig(
    enabled: true,
    sensitivity: SpoofSensitivity.maximum,
    minFactorsForDetection: 1,
    blockMockLocations: true,
    checkMockProvider: true,
    checkDeveloperOptions: true,
    checkMockMode: true,
    maxPossibleSpeedKph: 350, // High-speed train max
  );

  /// Creates a copy with the given fields replaced.
  SpoofDetectionConfig copyWith({
    bool? enabled,
    bool? blockMockLocations,
    SpoofSensitivity? sensitivity,
    double? maxPossibleSpeedKph,
    double? maxAltitudeChangePerSecond,
    int? minFactorsForDetection,
    void Function(SpoofDetectionEvent)? onSpoofDetected,
    bool? checkMockProvider,
    bool? checkDeveloperOptions,
    bool? checkMockMode,
    List<String>? trustedMockProviders,
  }) {
    return SpoofDetectionConfig(
      enabled: enabled ?? this.enabled,
      blockMockLocations: blockMockLocations ?? this.blockMockLocations,
      sensitivity: sensitivity ?? this.sensitivity,
      maxPossibleSpeedKph: maxPossibleSpeedKph ?? this.maxPossibleSpeedKph,
      maxAltitudeChangePerSecond:
          maxAltitudeChangePerSecond ?? this.maxAltitudeChangePerSecond,
      minFactorsForDetection:
          minFactorsForDetection ?? this.minFactorsForDetection,
      onSpoofDetected: onSpoofDetected ?? this.onSpoofDetected,
      checkMockProvider: checkMockProvider ?? this.checkMockProvider,
      checkDeveloperOptions:
          checkDeveloperOptions ?? this.checkDeveloperOptions,
      checkMockMode: checkMockMode ?? this.checkMockMode,
      trustedMockProviders: trustedMockProviders ?? this.trustedMockProviders,
    );
  }

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'enabled': enabled,
        'blockMockLocations': blockMockLocations,
        'sensitivity': sensitivity.name,
        'maxPossibleSpeedKph': maxPossibleSpeedKph,
        'maxAltitudeChangePerSecond': maxAltitudeChangePerSecond,
        'minFactorsForDetection': minFactorsForDetection,
        'checkMockProvider': checkMockProvider,
        'checkDeveloperOptions': checkDeveloperOptions,
        'checkMockMode': checkMockMode,
        'trustedMockProviders': trustedMockProviders,
      };

  /// Creates from a map.
  factory SpoofDetectionConfig.fromMap(JsonMap map) {
    return SpoofDetectionConfig(
      enabled: map['enabled'] as bool? ?? true,
      blockMockLocations: map['blockMockLocations'] as bool? ?? false,
      sensitivity: SpoofSensitivity.values.firstWhere(
        (e) => e.name == map['sensitivity'],
        orElse: () => SpoofSensitivity.balanced,
      ),
      maxPossibleSpeedKph:
          (map['maxPossibleSpeedKph'] as num?)?.toDouble() ?? 1200,
      maxAltitudeChangePerSecond:
          (map['maxAltitudeChangePerSecond'] as num?)?.toDouble() ?? 100,
      minFactorsForDetection:
          (map['minFactorsForDetection'] as num?)?.toInt() ?? 2,
      checkMockProvider: map['checkMockProvider'] as bool? ?? true,
      checkDeveloperOptions: map['checkDeveloperOptions'] as bool? ?? false,
      checkMockMode: map['checkMockMode'] as bool? ?? true,
      trustedMockProviders: map['trustedMockProviders'] is List
          ? List<String>.from(map['trustedMockProviders'] as List)
          : const [],
    );
  }
}

/// Sensitivity level for spoof detection.
enum SpoofSensitivity {
  /// Minimal detection - only obvious spoofing.
  low,

  /// Balanced detection (default).
  balanced,

  /// Aggressive detection - may have some false positives.
  high,

  /// Maximum detection - for high-security applications.
  maximum,
}

/// Event emitted when spoofing is detected.
class SpoofDetectionEvent {
  /// The suspicious location.
  final Location location;

  /// Previous location for comparison.
  final Location? previousLocation;

  /// Detection factors that triggered this event.
  final Set<SpoofFactor> factors;

  /// Confidence score (0-1) that this is actually spoofed.
  final double confidence;

  /// Whether the location was blocked from being emitted.
  final bool wasBlocked;

  /// Timestamp of detection.
  final DateTime timestamp;

  /// Additional details about detection.
  final Map<String, dynamic> details;

  /// Creates a spoof detection event.
  SpoofDetectionEvent({
    required this.location,
    this.previousLocation,
    required this.factors,
    required this.confidence,
    this.wasBlocked = false,
    Map<String, dynamic>? details,
    DateTime? timestamp,
  })  : details = details ?? const {},
        timestamp = timestamp ?? DateTime.now();

  /// Human-readable description of the detection.
  String get description {
    final buffer = StringBuffer();
    buffer.write(
        'Spoof detected (${(confidence * 100).toStringAsFixed(0)}% confidence): ');
    buffer.write(factors.map((f) => f.description).join(', '));
    return buffer.toString();
  }

  /// Converts to a JSON-serializable map.
  JsonMap toMap() => {
        'location': location.toMap(),
        if (previousLocation != null)
          'previousLocation': previousLocation!.toMap(),
        'factors': factors.map((f) => f.name).toList(),
        'confidence': confidence,
        'wasBlocked': wasBlocked,
        'timestamp': timestamp.toIso8601String(),
        'details': details,
      };
}

/// Factors that can indicate location spoofing.
enum SpoofFactor {
  /// Android: Location marked as from mock provider.
  mockProvider,

  /// Device has developer options enabled.
  developerOptionsEnabled,

  /// Location app in mock mode.
  mockModeEnabled,

  /// Physically impossible speed detected.
  impossibleSpeed,

  /// Physically impossible altitude change.
  impossibleAltitudeChange,

  /// Location accuracy suspiciously perfect.
  suspiciousAccuracy,

  /// Repeated identical coordinates.
  repeatedCoordinates,

  /// GPS timestamp doesn't match system time.
  timestampMismatch,

  /// No GPS satellites used for fix.
  noSatellites,

  /// Altitude missing or zero (common in spoofed locations).
  missingAltitude,

  /// Location provider inconsistency.
  providerInconsistency,

  /// Speed reported vs calculated mismatch.
  speedMismatch,

  /// Known spoofing app signature detected.
  spoofingAppDetected,
}

/// Extension to get human-readable descriptions.
extension SpoofFactorDescription on SpoofFactor {
  /// Human-readable description of this factor.
  String get description {
    switch (this) {
      case SpoofFactor.mockProvider:
        return 'Mock location provider';
      case SpoofFactor.developerOptionsEnabled:
        return 'Developer options enabled';
      case SpoofFactor.mockModeEnabled:
        return 'Mock mode active';
      case SpoofFactor.impossibleSpeed:
        return 'Impossible speed';
      case SpoofFactor.impossibleAltitudeChange:
        return 'Impossible altitude change';
      case SpoofFactor.suspiciousAccuracy:
        return 'Suspiciously perfect accuracy';
      case SpoofFactor.repeatedCoordinates:
        return 'Repeated coordinates';
      case SpoofFactor.timestampMismatch:
        return 'Timestamp mismatch';
      case SpoofFactor.noSatellites:
        return 'No GPS satellites';
      case SpoofFactor.missingAltitude:
        return 'Missing altitude';
      case SpoofFactor.providerInconsistency:
        return 'Provider inconsistency';
      case SpoofFactor.speedMismatch:
        return 'Speed mismatch';
      case SpoofFactor.spoofingAppDetected:
        return 'Spoofing app detected';
    }
  }
}

/// Analyzer for detecting spoofed locations.
class SpoofDetector {
  final SpoofDetectionConfig config;
  Location? _previousLocation;
  int _repeatedCoordCount = 0;
  static const _repeatedThreshold = 3;

  /// Creates a spoof detector with the given configuration.
  SpoofDetector(this.config);

  /// Analyzes a location for spoofing indicators.
  ///
  /// Returns null if no spoofing detected, or a [SpoofDetectionEvent]
  /// if suspicious.
  SpoofDetectionEvent? analyze(Location location, {bool? isMockProvider}) {
    if (!config.enabled) return null;

    final factors = <SpoofFactor>{};
    final details = <String, dynamic>{};

    // Check mock provider (Android)
    if (config.checkMockProvider && isMockProvider == true) {
      factors.add(SpoofFactor.mockProvider);
    }

    // Check for repeated identical coordinates
    if (_previousLocation != null) {
      final isSameLocation =
          _previousLocation!.coords.latitude == location.coords.latitude &&
              _previousLocation!.coords.longitude == location.coords.longitude;
      if (isSameLocation) {
        _repeatedCoordCount++;
        if (_repeatedCoordCount >= _repeatedThreshold) {
          factors.add(SpoofFactor.repeatedCoordinates);
          details['repeatedCount'] = _repeatedCoordCount;
        }
      } else {
        _repeatedCoordCount = 0;
      }

      // Check for impossible speed
      final distance = LocationUtils.calculateDistance(
        _previousLocation!.coords,
        location.coords,
      );
      final duration =
          location.timestamp.difference(_previousLocation!.timestamp);
      final calculatedSpeedKph =
          LocationUtils.calculateSpeedKph(distance, duration);

      if (calculatedSpeedKph > config.maxPossibleSpeedKph) {
        factors.add(SpoofFactor.impossibleSpeed);
        details['calculatedSpeedKph'] = calculatedSpeedKph;
      }

      // Check for speed mismatch
      final reportedSpeedKph = (location.coords.speed ?? 0) * 3.6;
      if (calculatedSpeedKph > 10 && reportedSpeedKph > 0) {
        final speedRatio = calculatedSpeedKph / reportedSpeedKph;
        if (speedRatio < 0.1 || speedRatio > 10) {
          factors.add(SpoofFactor.speedMismatch);
          details['reportedSpeedKph'] = reportedSpeedKph;
          details['calculatedSpeedKph'] = calculatedSpeedKph;
        }
      }

      // Check for impossible altitude change
      final prevAlt = _previousLocation!.coords.altitude;
      final currAlt = location.coords.altitude;
      if (prevAlt != null && currAlt != null) {
        final duration = location.timestamp
            .difference(_previousLocation!.timestamp)
            .inSeconds;
        if (duration > 0) {
          final altChangePerSec = (currAlt - prevAlt).abs() / duration;
          if (altChangePerSec > config.maxAltitudeChangePerSecond) {
            factors.add(SpoofFactor.impossibleAltitudeChange);
            details['altitudeChangePerSec'] = altChangePerSec;
          }
        }
      }
    }

    // Check for suspicious accuracy (too perfect)
    final accuracy = location.coords.accuracy;
    if (config.sensitivity == SpoofSensitivity.high ||
        config.sensitivity == SpoofSensitivity.maximum) {
      if (accuracy > 0 && accuracy < 1) {
        factors.add(SpoofFactor.suspiciousAccuracy);
        details['accuracy'] = accuracy;
      }
    }

    // Check for missing altitude (common in spoofed locations)
    if (config.sensitivity == SpoofSensitivity.maximum) {
      if (location.coords.altitude == null || location.coords.altitude == 0) {
        factors.add(SpoofFactor.missingAltitude);
      }
    }

    // Save previous location BEFORE updating for event creation
    final oldPreviousLocation = _previousLocation;
    _previousLocation = location;

    // Determine if we should flag this as spoofed
    if (factors.length >= config.minFactorsForDetection) {
      // Calculate confidence based on number and type of factors
      final confidence = _calculateConfidence(factors);

      final event = SpoofDetectionEvent(
        location: location,
        previousLocation: oldPreviousLocation,
        factors: factors,
        confidence: confidence,
        wasBlocked: config.blockMockLocations,
        details: details,
      );

      // Trigger callback
      config.onSpoofDetected?.call(event);

      return event;
    }

    return null;
  }

  double _calculateConfidence(Set<SpoofFactor> factors) {
    // Higher weight factors
    const weights = {
      SpoofFactor.mockProvider: 0.9,
      SpoofFactor.spoofingAppDetected: 0.95,
      SpoofFactor.impossibleSpeed: 0.8,
      SpoofFactor.impossibleAltitudeChange: 0.7,
      SpoofFactor.repeatedCoordinates: 0.6,
      SpoofFactor.speedMismatch: 0.5,
      SpoofFactor.suspiciousAccuracy: 0.4,
      SpoofFactor.missingAltitude: 0.3,
      SpoofFactor.timestampMismatch: 0.5,
      SpoofFactor.noSatellites: 0.4,
      SpoofFactor.providerInconsistency: 0.5,
      SpoofFactor.developerOptionsEnabled: 0.3,
      SpoofFactor.mockModeEnabled: 0.6,
    };

    if (factors.isEmpty) return 0;

    double total = 0;
    for (final factor in factors) {
      total += weights[factor] ?? 0.5;
    }

    // Combine: more factors = higher confidence
    return (total / factors.length * (1 + factors.length * 0.1)).clamp(0, 1);
  }

  /// Resets the detector state.
  void reset() {
    _previousLocation = null;
    _repeatedCoordCount = 0;
  }
}
