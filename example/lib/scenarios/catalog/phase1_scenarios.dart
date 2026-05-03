/// Phase-1 scenario catalog: the scenarios that exercise the SDK without
/// requiring the mock HTTP backend. Phase-2 (HTTP-adversarial, requires
/// MockBackend) is registered separately.
library;

import 'package:locus_example/scenarios/catalog/geofence_add_remove_scenario.dart';
import 'package:locus_example/scenarios/catalog/sync_pause_resume_scenario.dart';
import 'package:locus_example/scenarios/catalog/tracking_lifecycle_scenario.dart';
import 'package:locus_example/scenarios/scenario.dart';

/// Builds the canonical ordered list of Phase-1 scenarios.
///
/// Returns fresh instances on every call so the runner can reset internal
/// state between full passes without leaking references across runs. Order
/// is intentional and roughly mirrors the SDK boot sequence: tracking
/// lifecycle first, then sync, then geofencing.
List<Scenario> phase1Scenarios() => <Scenario>[
      TrackingLifecycleScenario(),
      SyncPauseResumeScenario(),
      GeofenceAddRemoveScenario(),
    ];
