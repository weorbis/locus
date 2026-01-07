enum MigrationConfidence {
  high,
  medium,
  low,
}

enum MigrationCategory {
  location,
  geofencing,
  privacy,
  trips,
  sync,
  battery,
  diagnostics,
  removed,
}

class PatternMatch {
  final String filePath;
  final int line;
  final int column;
  final String original;
  final String replacement;
  final String patternId;

  PatternMatch({
    required this.filePath,
    required this.line,
    required this.column,
    required this.original,
    required this.replacement,
    required this.patternId,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'line': line,
        'column': column,
        'original': original,
        'replacement': replacement,
        'patternId': patternId,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PatternMatch &&
          runtimeType == other.runtimeType &&
          filePath == other.filePath &&
          line == other.line &&
          original == other.original;

  @override
  int get hashCode => Object.hash(filePath, line, original);
}

class MigrationPattern {
  final String id;
  final String name;
  final String description;
  final MigrationConfidence confidence;
  final MigrationCategory category;
  final String fromPattern;
  final String toPatternTemplate;

  const MigrationPattern({
    required this.id,
    required this.name,
    required this.description,
    required this.confidence,
    required this.category,
    required this.fromPattern,
    required this.toPatternTemplate,
  });

  List<PatternMatch> findMatches(String content, String filePath) {
    final matches = <PatternMatch>[];
    final lines = content.split('\n');
    final regex = RegExp(fromPattern);

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final match = regex.firstMatch(line);

      if (match != null) {
        final replacement = _buildReplacement(match);
        matches.add(PatternMatch(
          filePath: filePath,
          line: i + 1,
          column: match.start,
          original: match.group(0)!,
          replacement: replacement,
          patternId: id,
        ));
      }
    }

    return matches;
  }

  String _buildReplacement(Match match) {
    String replacement = toPatternTemplate;

    for (int i = 1; i <= match.groupCount; i++) {
      final placeholder = '\$$i';
      if (replacement.contains(placeholder)) {
        replacement = replacement.replaceAll(placeholder, match.group(i) ?? '');
      }
    }

    return replacement;
  }
}

class MigrationPatternDatabase {
  static final List<MigrationPattern> allPatterns = [
    ..._importPatterns,
    ..._configPatterns,
    ..._locationPatterns,
    ..._geofencingPatterns,
    ..._privacyPatterns,
    ..._tripPatterns,
    ..._syncPatterns,
    ..._batteryPatterns,
    ..._diagnosticsPatterns,
    ..._removedPatterns,
    ..._headlessPatterns,
  ];

  /// Import statement patterns - detect outdated imports
  static const _importPatterns = [
    MigrationPattern(
      id: 'locus-import-services',
      name: 'Import pattern unchanged but may need service exports',
      description:
          'The import remains the same but ensure you access services via Locus.location, Locus.geofencing, etc.',
      confidence: MigrationConfidence.medium,
      category: MigrationCategory.location,
      fromPattern: r"import 'package:locus/locus\.dart'",
      toPatternTemplate: "import 'package:locus/locus.dart'",
    ),
  ];

  /// Configuration patterns - LocusConfig changes
  static const _configPatterns = [
    MigrationPattern(
      id: 'locus-config-url',
      name: 'LocusConfig.url → LocusConfig.syncUrl',
      description: 'The url parameter was renamed to syncUrl for clarity',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.sync,
      fromPattern: r'LocusConfig\(([^)]*)\burl:',
      toPatternTemplate: 'LocusConfig(\$1syncUrl:',
    ),
    MigrationPattern(
      id: 'locus-config-http-timeout',
      name: 'LocusConfig.httpTimeout → LocusConfig.syncTimeout',
      description: 'The httpTimeout parameter was renamed to syncTimeout',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.sync,
      fromPattern: r'httpTimeout:',
      toPatternTemplate: 'syncTimeout:',
    ),
    MigrationPattern(
      id: 'locus-set-config',
      name: 'Locus.setConfig() still works but prefer passing to ready()',
      description:
          'setConfig still works but configuration is best passed to Locus.ready(config:)',
      confidence: MigrationConfidence.medium,
      category: MigrationCategory.location,
      fromPattern: r'Locus\.setConfig\(([^)]+)\)',
      toPatternTemplate: 'Locus.setConfig(\$1)',
    ),
  ];

  static const _locationPatterns = [
    MigrationPattern(
      id: 'locus-get-current-position',
      name: 'Locus.location.getCurrentPosition() → Locus.location.getCurrentPosition()',
      description: 'Migrate getCurrentPosition to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.location,
      fromPattern: r'Locus\.getCurrentPosition\(([^)]*)\)',
      toPatternTemplate: 'Locus.location.getCurrentPosition(\$1)',
    ),
    MigrationPattern(
      id: 'locus-location-stream',
      name: 'Locus.locationStream → Locus.location.stream',
      description: 'Migrate locationStream to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.location,
      fromPattern: r'Locus\.locationStream',
      toPatternTemplate: 'Locus.location.stream',
    ),
    MigrationPattern(
      id: 'locus-motion-change-stream',
      name: 'Locus.motionChangeStream → Locus.location.motionChanges',
      description: 'Migrate motionChangeStream to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.location,
      fromPattern: r'Locus\.motionChangeStream',
      toPatternTemplate: 'Locus.location.motionChanges',
    ),
    MigrationPattern(
      id: 'locus-heartbeat-stream',
      name: 'Locus.heartbeatStream → Locus.location.heartbeats',
      description: 'Migrate heartbeatStream to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.location,
      fromPattern: r'Locus\.heartbeatStream',
      toPatternTemplate: 'Locus.location.heartbeats',
    ),
    MigrationPattern(
      id: 'locus-on-location-callback',
      name: 'Locus.onLocation(cb) → Locus.location.onLocation(cb)',
      description: 'Migrate onLocation callback to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.location,
      fromPattern: r'Locus\.onLocation\(([^)]+)\)',
      toPatternTemplate: 'Locus.location.onLocation(\$1)',
    ),
    MigrationPattern(
      id: 'locus-on-motion-change-callback',
      name: 'Locus.onMotionChange(cb) → Locus.location.onMotionChange(cb)',
      description: 'Migrate onMotionChange callback to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.location,
      fromPattern: r'Locus\.onMotionChange\(([^)]+)\)',
      toPatternTemplate: 'Locus.location.onMotionChange(\$1)',
    ),
    MigrationPattern(
      id: 'locus-on-heartbeat-callback',
      name: 'Locus.onHeartbeat(cb) → Locus.location.onHeartbeat(cb)',
      description: 'Migrate onHeartbeat callback to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.location,
      fromPattern: r'Locus\.onHeartbeat\(([^)]+)\)',
      toPatternTemplate: 'Locus.location.onHeartbeat(\$1)',
    ),
    MigrationPattern(
      id: 'locus-change-pace',
      name: 'Locus.changePace() → Locus.location.changePace()',
      description: 'Migrate changePace to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.location,
      fromPattern: r'Locus\.changePace\(([^)]+)\)',
      toPatternTemplate: 'Locus.location.changePace(\$1)',
    ),
    MigrationPattern(
      id: 'locus-set-odometer',
      name: 'Locus.location.setOdometer() → Locus.location.setOdometer()',
      description: 'Migrate setOdometer to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.location,
      fromPattern: r'Locus\.setOdometer\(([^)]+)\)',
      toPatternTemplate: 'Locus.location.setOdometer(\$1)',
    ),
    MigrationPattern(
      id: 'locus-get-locations',
      name: 'Locus.location.getLocations() → Locus.location.getLocations()',
      description: 'Migrate getLocations to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.location,
      fromPattern: r'Locus\.getLocations\(([^)]*)\)',
      toPatternTemplate: 'Locus.location.getLocations(\$1)',
    ),
    MigrationPattern(
      id: 'locus-query-locations',
      name: 'Locus.location.queryLocations() → Locus.location.query()',
      description: 'Migrate queryLocations to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.location,
      fromPattern: r'Locus\.queryLocations\(([^)]+)\)',
      toPatternTemplate: 'Locus.location.query(\$1)',
    ),
    MigrationPattern(
      id: 'locus-get-location-summary',
      name: 'Locus.getLocationSummary() → Locus.location.getSummary()',
      description: 'Migrate getLocationSummary to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.location,
      fromPattern: r'Locus\.getLocationSummary\(([^)]*)\)',
      toPatternTemplate: 'Locus.location.getSummary(\$1)',
    ),
  ];

  static const _geofencingPatterns = [
    MigrationPattern(
      id: 'locus-add-geofence',
      name: 'Locus.addGeofence() → Locus.geofencing.add()',
      description: 'Migrate addGeofence to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.geofencing,
      fromPattern: r'Locus\.addGeofence\(([^)]+)\)',
      toPatternTemplate: 'Locus.geofencing.add(\$1)',
    ),
    MigrationPattern(
      id: 'locus-add-geofences',
      name: 'Locus.addGeofences() → Locus.geofencing.addAll()',
      description: 'Migrate addGeofences to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.geofencing,
      fromPattern: r'Locus\.addGeofences\(([^)]+)\)',
      toPatternTemplate: 'Locus.geofencing.addAll(\$1)',
    ),
    MigrationPattern(
      id: 'locus-remove-geofence',
      name: 'Locus.removeGeofence() → Locus.geofencing.remove()',
      description: 'Migrate removeGeofence to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.geofencing,
      fromPattern: r'Locus\.removeGeofence\(([^)]+)\)',
      toPatternTemplate: 'Locus.geofencing.remove(\$1)',
    ),
    MigrationPattern(
      id: 'locus-remove-geofences',
      name: 'Locus.geofencing.removeAll() → Locus.geofencing.removeAll()',
      description: 'Migrate removeGeofences to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.geofencing,
      fromPattern: r'Locus\.removeGeofences\(\)',
      toPatternTemplate: 'Locus.geofencing.removeAll()',
    ),
    MigrationPattern(
      id: 'locus-get-geofences',
      name: 'Locus.getGeofences() → Locus.geofencing.getAll()',
      description: 'Migrate getGeofences to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.geofencing,
      fromPattern: r'Locus\.getGeofences\(\)',
      toPatternTemplate: 'Locus.geofencing.getAll()',
    ),
    MigrationPattern(
      id: 'locus-get-geofence',
      name: 'Locus.getGeofence() → Locus.geofencing.get()',
      description: 'Migrate getGeofence to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.geofencing,
      fromPattern: r'Locus\.getGeofence\(([^)]+)\)',
      toPatternTemplate: 'Locus.geofencing.get(\$1)',
    ),
    MigrationPattern(
      id: 'locus-geofence-exists',
      name: 'Locus.geofenceExists() → Locus.geofencing.exists()',
      description: 'Migrate geofenceExists to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.geofencing,
      fromPattern: r'Locus\.geofenceExists\(([^)]+)\)',
      toPatternTemplate: 'Locus.geofencing.exists(\$1)',
    ),
    MigrationPattern(
      id: 'locus-start-geofences',
      name: 'Locus.startGeofences() → Locus.geofencing.startMonitoring()',
      description: 'Migrate startGeofences to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.geofencing,
      fromPattern: r'Locus\.startGeofences\(\)',
      toPatternTemplate: 'Locus.geofencing.startMonitoring()',
    ),
    MigrationPattern(
      id: 'locus-add-polygon-geofence',
      name: 'Locus.addPolygonGeofence() → Locus.geofencing.addPolygon()',
      description: 'Migrate addPolygonGeofence to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.geofencing,
      fromPattern: r'Locus\.addPolygonGeofence\(([^)]+)\)',
      toPatternTemplate: 'Locus.geofencing.addPolygon(\$1)',
    ),
    MigrationPattern(
      id: 'locus-add-polygon-geofences',
      name: 'Locus.addPolygonGeofences() → Locus.geofencing.addPolygons()',
      description: 'Migrate addPolygonGeofences to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.geofencing,
      fromPattern: r'Locus\.addPolygonGeofences\(([^)]+)\)',
      toPatternTemplate: 'Locus.geofencing.addPolygons(\$1)',
    ),
    MigrationPattern(
      id: 'locus-remove-polygon-geofence',
      name: 'Locus.removePolygonGeofence() → Locus.geofencing.removePolygon()',
      description: 'Migrate removePolygonGeofence to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.geofencing,
      fromPattern: r'Locus\.removePolygonGeofence\(([^)]+)\)',
      toPatternTemplate: 'Locus.geofencing.removePolygon(\$1)',
    ),
    MigrationPattern(
      id: 'locus-get-polygon-geofences',
      name: 'Locus.getPolygonGeofences() → Locus.geofencing.getAllPolygons()',
      description: 'Migrate getPolygonGeofences to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.geofencing,
      fromPattern: r'Locus\.getPolygonGeofences\(\)',
      toPatternTemplate: 'Locus.geofencing.getAllPolygons()',
    ),
    MigrationPattern(
      id: 'locus-geofence-stream',
      name: 'Locus.geofenceStream → Locus.geofencing.events',
      description: 'Migrate geofenceStream to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.geofencing,
      fromPattern: r'Locus\.geofenceStream',
      toPatternTemplate: 'Locus.geofencing.events',
    ),
    MigrationPattern(
      id: 'locus-on-geofence-callback',
      name: 'Locus.onGeofence(cb) → Locus.geofencing.onGeofence(cb)',
      description: 'Migrate geofence callback to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.geofencing,
      fromPattern: r'Locus\.onGeofence\(([^)]+)\)',
      toPatternTemplate: 'Locus.geofencing.onGeofence(\$1)',
    ),
    MigrationPattern(
      id: 'locus-workflow-events',
      name: 'Locus.workflowEvents → Locus.geofencing.workflowEvents',
      description: 'Migrate workflow events to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.geofencing,
      fromPattern: r'Locus\.workflowEvents',
      toPatternTemplate: 'Locus.geofencing.workflowEvents',
    ),
  ];

  static const _privacyPatterns = [
    MigrationPattern(
      id: 'locus-add-privacy-zone',
      name: 'Locus.addPrivacyZone() → Locus.privacy.add()',
      description: 'Migrate addPrivacyZone to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.privacy,
      fromPattern: r'Locus\.addPrivacyZone\(([^)]+)\)',
      toPatternTemplate: 'Locus.privacy.add(\$1)',
    ),
    MigrationPattern(
      id: 'locus-add-privacy-zones',
      name: 'Locus.addPrivacyZones() → Locus.privacy.addAll()',
      description: 'Migrate addPrivacyZones to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.privacy,
      fromPattern: r'Locus\.addPrivacyZones\(([^)]+)\)',
      toPatternTemplate: 'Locus.privacy.addAll(\$1)',
    ),
    MigrationPattern(
      id: 'locus-remove-privacy-zone',
      name: 'Locus.removePrivacyZone() → Locus.privacy.remove()',
      description: 'Migrate removePrivacyZone to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.privacy,
      fromPattern: r'Locus\.removePrivacyZone\(([^)]+)\)',
      toPatternTemplate: 'Locus.privacy.remove(\$1)',
    ),
    MigrationPattern(
      id: 'locus-remove-all-privacy-zones',
      name: 'Locus.removeAllPrivacyZones() → Locus.privacy.removeAll()',
      description: 'Migrate removeAllPrivacyZones to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.privacy,
      fromPattern: r'Locus\.removeAllPrivacyZones\(\)',
      toPatternTemplate: 'Locus.privacy.removeAll()',
    ),
    MigrationPattern(
      id: 'locus-get-privacy-zone',
      name: 'Locus.getPrivacyZone() → Locus.privacy.get()',
      description: 'Migrate getPrivacyZone to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.privacy,
      fromPattern: r'Locus\.getPrivacyZone\(([^)]+)\)',
      toPatternTemplate: 'Locus.privacy.get(\$1)',
    ),
    MigrationPattern(
      id: 'locus-get-privacy-zones',
      name: 'Locus.getPrivacyZones() → Locus.privacy.getAll()',
      description: 'Migrate getPrivacyZones to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.privacy,
      fromPattern: r'Locus\.getPrivacyZones\(\)',
      toPatternTemplate: 'Locus.privacy.getAll()',
    ),
    MigrationPattern(
      id: 'locus-set-privacy-zone-enabled',
      name: 'Locus.setPrivacyZoneEnabled() → Locus.privacy.setEnabled()',
      description: 'Migrate setPrivacyZoneEnabled to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.privacy,
      fromPattern: r'Locus\.setPrivacyZoneEnabled\(([^)]+)\)',
      toPatternTemplate: 'Locus.privacy.setEnabled(\$1)',
    ),
    MigrationPattern(
      id: 'locus-privacy-zone-events',
      name: 'Locus.privacyZoneEvents → Locus.privacy.events',
      description: 'Migrate privacyZoneEvents to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.privacy,
      fromPattern: r'Locus\.privacyZoneEvents',
      toPatternTemplate: 'Locus.privacy.events',
    ),
    MigrationPattern(
      id: 'locus-on-privacy-zone-change',
      name: 'Locus.onPrivacyZoneChange() → Locus.privacy.onChange()',
      description: 'Migrate privacy zone change callback to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.privacy,
      fromPattern: r'Locus\.onPrivacyZoneChange\(([^)]+)\)',
      toPatternTemplate: 'Locus.privacy.onChange(\$1)',
    ),
  ];

  static const _tripPatterns = [
    MigrationPattern(
      id: 'locus-start-trip',
      name: 'Locus.trips.start() → Locus.trips.start()',
      description: 'Migrate startTrip to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.trips,
      fromPattern: r'Locus\.startTrip\(([^)]+)\)',
      toPatternTemplate: 'Locus.trips.start(\$1)',
    ),
    MigrationPattern(
      id: 'locus-stop-trip',
      name: 'Locus.stopTrip() → Locus.trips.stop()',
      description: 'Migrate stopTrip to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.trips,
      fromPattern: r'Locus\.stopTrip\(\)',
      toPatternTemplate: 'Locus.trips.stop()',
    ),
    MigrationPattern(
      id: 'locus-get-trip-state',
      name: 'Locus.getTripState() → Locus.trips.getState()',
      description: 'Migrate getTripState to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.trips,
      fromPattern: r'Locus\.getTripState\(\)',
      toPatternTemplate: 'Locus.trips.getState()',
    ),
    MigrationPattern(
      id: 'locus-trip-events',
      name: 'Locus.tripEvents → Locus.trips.events',
      description: 'Migrate trip events to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.trips,
      fromPattern: r'Locus\.tripEvents',
      toPatternTemplate: 'Locus.trips.events',
    ),
    MigrationPattern(
      id: 'locus-on-trip-event',
      name: 'Locus.trips.events.listen() → Locus.trips.onEvent()',
      description: 'Migrate trip event callback to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.trips,
      fromPattern: r'Locus\.onTripEvent\(([^)]+)\)',
      toPatternTemplate: 'Locus.trips.onEvent(\$1)',
    ),
  ];

  static const _syncPatterns = [
    MigrationPattern(
      id: 'locus-sync',
      name: 'Locus.sync() → Locus.dataSync.now()',
      description: 'Migrate sync to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.sync,
      fromPattern: r'Locus\.sync\(\)',
      toPatternTemplate: 'Locus.dataSync.now()',
    ),
    MigrationPattern(
      id: 'locus-resume-sync',
      name: 'Locus.resumeSync() → Locus.dataSync.resume()',
      description: 'Migrate resumeSync to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.sync,
      fromPattern: r'Locus\.resumeSync\(\)',
      toPatternTemplate: 'Locus.dataSync.resume()',
    ),
    MigrationPattern(
      id: 'locus-destroy-locations',
      name: 'Locus.location.destroyLocations() → Locus.location.destroyLocations()',
      description: 'Migrate destroyLocations to location service',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.sync,
      fromPattern: r'Locus\.destroyLocations\(\)',
      toPatternTemplate: 'Locus.location.destroyLocations()',
    ),
    MigrationPattern(
      id: 'locus-enqueue',
      name: 'Locus.enqueue() → Locus.dataSync.enqueue()',
      description: 'Migrate enqueue to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.sync,
      fromPattern: r'Locus\.enqueue\(([^)]+)\)',
      toPatternTemplate: 'Locus.dataSync.enqueue(\$1)',
    ),
    MigrationPattern(
      id: 'locus-get-queue',
      name: 'Locus.getQueue() → Locus.dataSync.getQueue()',
      description: 'Migrate getQueue to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.sync,
      fromPattern: r'Locus\.getQueue\(([^)]*)\)',
      toPatternTemplate: 'Locus.dataSync.getQueue(\$1)',
    ),
    MigrationPattern(
      id: 'locus-clear-queue',
      name: 'Locus.clearQueue() → Locus.dataSync.clearQueue()',
      description: 'Migrate clearQueue to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.sync,
      fromPattern: r'Locus\.clearQueue\(\)',
      toPatternTemplate: 'Locus.dataSync.clearQueue()',
    ),
    MigrationPattern(
      id: 'locus-sync-queue',
      name: 'Locus.syncQueue() → Locus.dataSync.syncQueue()',
      description: 'Migrate syncQueue to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.sync,
      fromPattern: r'Locus\.syncQueue\(([^)]*)\)',
      toPatternTemplate: 'Locus.dataSync.syncQueue(\$1)',
    ),
    MigrationPattern(
      id: 'locus-http-stream',
      name: 'Locus.httpStream → Locus.dataSync.events',
      description: 'Migrate httpStream to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.sync,
      fromPattern: r'Locus\.httpStream',
      toPatternTemplate: 'Locus.dataSync.events',
    ),
    MigrationPattern(
      id: 'locus-on-http',
      name: 'Locus.onHttp() → Locus.dataSync.onHttp()',
      description: 'Convert HTTP event callback to service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.sync,
      fromPattern: r'Locus\.onHttp\(([^)]+)\)',
      toPatternTemplate: 'Locus.dataSync.onHttp(\$1)',
    ),
    MigrationPattern(
      id: 'locus-set-sync-policy',
      name: 'Locus.setSyncPolicy() → Locus.dataSync.setPolicy()',
      description: 'Migrate setSyncPolicy to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.sync,
      fromPattern: r'Locus\.setSyncPolicy\(([^)]+)\)',
      toPatternTemplate: 'Locus.dataSync.setPolicy(\$1)',
    ),
  ];

  static const _batteryPatterns = [
    MigrationPattern(
      id: 'locus-get-battery-stats',
      name: 'Locus.getBatteryStats() → Locus.battery.getStats()',
      description: 'Migrate getBatteryStats to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.battery,
      fromPattern: r'Locus\.getBatteryStats\(\)',
      toPatternTemplate: 'Locus.battery.getStats()',
    ),
    MigrationPattern(
      id: 'locus-get-power-state',
      name: 'Locus.getPowerState() → Locus.battery.getPowerState()',
      description: 'Migrate getPowerState to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.battery,
      fromPattern: r'Locus\.getPowerState\(\)',
      toPatternTemplate: 'Locus.battery.getPowerState()',
    ),
    MigrationPattern(
      id: 'locus-estimate-battery-runway',
      name: 'Locus.estimateBatteryRunway() → Locus.battery.estimateRunway()',
      description: 'Migrate estimateBatteryRunway to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.battery,
      fromPattern: r'Locus\.estimateBatteryRunway\(\)',
      toPatternTemplate: 'Locus.battery.estimateRunway()',
    ),
    MigrationPattern(
      id: 'locus-set-adaptive-tracking',
      name: 'Locus.setAdaptiveTracking() → Locus.battery.setAdaptiveTracking()',
      description: 'Migrate setAdaptiveTracking to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.battery,
      fromPattern: r'Locus\.setAdaptiveTracking\(([^)]+)\)',
      toPatternTemplate: 'Locus.battery.setAdaptiveTracking(\$1)',
    ),
    MigrationPattern(
      id: 'locus-calculate-adaptive-settings',
      name:
          'Locus.calculateAdaptiveSettings() → Locus.battery.calculateAdaptiveSettings()',
      description: 'Migrate calculateAdaptiveSettings to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.battery,
      fromPattern: r'Locus\.calculateAdaptiveSettings\(\)',
      toPatternTemplate: 'Locus.battery.calculateAdaptiveSettings()',
    ),
    MigrationPattern(
      id: 'locus-power-state-stream',
      name: 'Locus.powerStateStream → Locus.battery.powerStateEvents',
      description: 'Migrate powerStateStream to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.battery,
      fromPattern: r'Locus\.powerStateStream',
      toPatternTemplate: 'Locus.battery.powerStateEvents',
    ),
    MigrationPattern(
      id: 'locus-power-save-stream',
      name: 'Locus.powerSaveStream → Locus.battery.powerSaveChanges',
      description: 'Migrate powerSaveStream to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.battery,
      fromPattern: r'Locus\.powerSaveStream',
      toPatternTemplate: 'Locus.battery.powerSaveChanges',
    ),
    MigrationPattern(
      id: 'locus-on-power-state-change',
      name: 'Locus.onPowerStateChangeWithObj() → Locus.battery.onPowerStateChange()',
      description: 'Migrate power state change callback to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.battery,
      fromPattern: r'Locus\.onPowerStateChangeWithObj\(([^)]+)\)',
      toPatternTemplate: 'Locus.battery.onPowerStateChange(\$1)',
    ),
    MigrationPattern(
      id: 'locus-on-power-save-change',
      name: 'Locus.onPowerSaveChange() → Locus.battery.onPowerSaveChange()',
      description: 'Migrate power save change callback to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.battery,
      fromPattern: r'Locus\.onPowerSaveChange\(([^)]+)\)',
      toPatternTemplate: 'Locus.battery.onPowerSaveChange(\$1)',
    ),
  ];

  static const _diagnosticsPatterns = [
    MigrationPattern(
      id: 'locus-get-diagnostics',
      name: 'Locus.getDiagnostics() → Locus.diagnostics.getDiagnostics()',
      description: 'Migrate getDiagnostics to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.diagnostics,
      fromPattern: r'Locus\.getDiagnostics\(\)',
      toPatternTemplate: 'Locus.diagnostics.getDiagnostics()',
    ),
    MigrationPattern(
      id: 'locus-get-log',
      name: 'Locus.getLog() → Locus.diagnostics.getLog()',
      description: 'Migrate getLog to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.diagnostics,
      fromPattern: r'Locus\.getLog\(\)',
      toPatternTemplate: 'Locus.diagnostics.getLog()',
    ),
    MigrationPattern(
      id: 'locus-location-anomalies',
      name: 'Locus.locationAnomalies() → Locus.diagnostics.locationAnomalies()',
      description: 'Migrate locationAnomalies to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.diagnostics,
      fromPattern: r'Locus\.locationAnomalies\(([^)]*)\)',
      toPatternTemplate: 'Locus.diagnostics.locationAnomalies(\$1)',
    ),
    MigrationPattern(
      id: 'locus-location-quality',
      name: 'Locus.locationQuality() → Locus.diagnostics.locationQuality()',
      description: 'Migrate locationQuality to new service pattern',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.diagnostics,
      fromPattern: r'Locus\.locationQuality\(([^)]*)\)',
      toPatternTemplate: 'Locus.diagnostics.locationQuality(\$1)',
    ),
  ];

  static const _removedPatterns = [
    MigrationPattern(
      id: 'locus-email-log',
      name: 'Locus.emailLog() → REMOVED',
      description:
          'emailLog feature removed in v2.0 - use your own email implementation',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.removed,
      fromPattern: r'Locus\.emailLog\([^)]+\)',
      toPatternTemplate:
          '// TODO: Locus.emailLog() removed in v2.0 - implement your own email feature',
    ),
    MigrationPattern(
      id: 'locus-play-sound',
      name: 'Locus.playSound() → REMOVED',
      description:
          'playSound feature removed in v2.0 - use Flutter sound package instead',
      confidence: MigrationConfidence.high,
      category: MigrationCategory.removed,
      fromPattern: r'Locus\.playSound\([^)]+\)',
      toPatternTemplate:
          '// TODO: Locus.playSound() removed in v2.0 - use flutter_sound package',
    ),
  ];

  static const _headlessPatterns = [
    MigrationPattern(
      id: 'locus-register-headless-task',
      name: 'Locus.registerHeadlessTask() → requires @pragma annotation',
      description:
          'Headless callbacks require @pragma("vm:entry-point") annotation',
      confidence: MigrationConfidence.low,
      category: MigrationCategory.sync,
      fromPattern: r'Locus\.registerHeadlessTask\(([^)]+)\)',
      toPatternTemplate:
          '@pragma(\'vm:entry-point\')\nLocus.registerHeadlessTask(\$1)',
    ),
    MigrationPattern(
      id: 'locus-register-headless-sync-body-builder',
      name:
          'Locus.registerHeadlessSyncBodyBuilder() → requires @pragma annotation',
      description:
          'Headless sync body builder requires @pragma("vm:entry-point") annotation',
      confidence: MigrationConfidence.low,
      category: MigrationCategory.sync,
      fromPattern: r'Locus\.registerHeadlessSyncBodyBuilder\(([^)]+)\)',
      toPatternTemplate:
          '@pragma(\'vm:entry-point\')\nLocus.registerHeadlessSyncBodyBuilder(\$1)',
    ),
  ];

  static List<MigrationPattern> getPatternsForCategory(
      MigrationCategory category) {
    return allPatterns.where((p) => p.category == category).toList();
  }

  static List<MigrationPattern> getHighConfidencePatterns() {
    return allPatterns
        .where((p) => p.confidence == MigrationConfidence.high)
        .toList();
  }

  static List<MigrationPattern> getLowConfidencePatterns() {
    return allPatterns
        .where((p) => p.confidence == MigrationConfidence.low)
        .toList();
  }

  static Map<MigrationCategory, int> getPatternCountByCategory() {
    final counts = <MigrationCategory, int>{};
    for (final pattern in allPatterns) {
      counts[pattern.category] = (counts[pattern.category] ?? 0) + 1;
    }
    return counts;
  }
}
