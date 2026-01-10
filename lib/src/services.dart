/// Services barrel - exports all services from features.
library;

// ============================================================
// v2.0 Service API
// ============================================================

// Service interfaces
export 'services/location_service.dart';
export 'services/geofence_service.dart';
export 'services/privacy_service.dart';
export 'services/trip_service.dart';
export 'services/sync_service.dart';
export 'services/battery_service.dart';
export 'services/diagnostics_service.dart';

// Service implementations
export 'services/location_service_impl.dart';
export 'services/geofence_service_impl.dart';
export 'services/privacy_service_impl.dart';
export 'services/trip_service_impl.dart';
export 'services/sync_service_impl.dart';
export 'services/battery_service_impl.dart';
export 'services/diagnostics_service_impl.dart';

// ============================================================
// Feature Services
// ============================================================

// Location services
export 'features/location/services/locus_location.dart';
export 'features/location/services/location_anomaly_detector.dart';
export 'features/location/services/location_quality_analyzer.dart';
export 'features/location/services/significant_change.dart';
export 'features/location/services/spoof_detection.dart';

// Geofencing services
export 'features/geofencing/services/locus_geofencing.dart';
export 'features/geofencing/services/locus_workflows.dart';
export 'features/geofencing/services/geofence_workflow_engine.dart';
export 'features/geofencing/services/polygon_geofence_service.dart';

// Battery services
export 'features/battery/services/locus_battery.dart';
export 'features/battery/services/locus_adaptive.dart';

// Privacy services
export 'features/privacy/services/privacy_zone_service.dart';

// Trips services
export 'features/trips/services/locus_trip.dart';
export 'features/trips/services/trip_engine.dart';
export 'features/trips/services/trip_store.dart';

// Tracking services
export 'features/tracking/services/locus_profiles.dart';
export 'features/tracking/services/tracking_profile_manager.dart';

// Sync services
export 'features/sync/services/locus_sync.dart';

// Diagnostics services
export 'features/diagnostics/services/locus_diagnostics.dart';
export 'features/diagnostics/services/error_recovery.dart';

// Core services
export 'core/device_optimization_service.dart';
export 'core/event_mapper.dart';
export 'core/permission_assistant.dart';
export 'core/permission_service.dart';
