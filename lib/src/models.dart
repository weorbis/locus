/// Models barrel - exports all models from features.
library;

// Shared models
export 'shared/models/activity.dart';
export 'shared/models/battery.dart';
export 'shared/models/coords.dart';
export 'shared/models/enums.dart';
export 'shared/models/json_map.dart';
export 'shared/models/geolocation_state.dart';
export 'shared/models/headless_event.dart';

// Location feature models
export 'features/location/models/location.dart';
export 'features/location/models/location_history.dart';
export 'features/location/models/location_quality.dart';
export 'features/location/models/provider_change_event.dart';

// Geofencing feature models
export 'features/geofencing/models/geofence.dart';
export 'features/geofencing/models/geofence_event.dart';
export 'features/geofencing/models/polygon_geofence.dart';
export 'features/geofencing/models/geofence_workflow.dart';
export 'features/geofencing/models/geofence_workflow_event.dart';
export 'features/geofencing/models/geofence_workflow_state.dart';
export 'features/geofencing/models/geofence_workflow_step.dart';

// Battery feature models
export 'features/battery/models/adaptive_tracking.dart';
export 'features/battery/models/battery_runway.dart';
export 'features/battery/models/battery_stats.dart';
export 'features/battery/models/power_state.dart';
export 'features/battery/models/sync_policy.dart';

// Privacy feature models
export 'features/privacy/models/privacy_zone.dart';

// Trips feature models
export 'features/trips/models/route_point.dart';
export 'features/trips/models/trip_config.dart';
export 'features/trips/models/trip_event.dart';
export 'features/trips/models/trip_state.dart';
export 'features/trips/models/trip_summary.dart';

// Sync feature models
export 'features/sync/models/connectivity_change_event.dart';
export 'features/sync/models/http_event.dart';
export 'features/sync/models/queue_item.dart';

// Tracking feature models
export 'features/tracking/models/tracking_profile.dart';
export 'features/tracking/models/tracking_profile_rule.dart';

// Diagnostics feature models
export 'features/diagnostics/models/diagnostics.dart';
export 'features/diagnostics/models/log_entry.dart';
