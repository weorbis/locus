import 'package:locus_example/scenarios/catalog/auth_401_pauses_sync_scenario.dart';
import 'package:locus_example/scenarios/catalog/auth_403_persistent_pause_scenario.dart';
import 'package:locus_example/scenarios/catalog/flaky_retry_succeeds_scenario.dart';
import 'package:locus_example/scenarios/catalog/headers_refresh_on_401_scenario.dart';
import 'package:locus_example/scenarios/catalog/http_415_compression_fallback_scenario.dart';
import 'package:locus_example/scenarios/catalog/outage_recovery_drain_scenario.dart';
import 'package:locus_example/scenarios/scenario.dart';

/// Phase 2 scenarios. Each one drives the in-process mock backend
/// (`HttpMockBackend`) into a specific adversarial mode and asserts that the
/// SDK's HTTP / sync layer handles it the way recent CHANGELOG fixes
/// require. Mock-free scenarios live in a separate barrel.
List<Scenario> phase2Scenarios() => <Scenario>[
      Auth401PausesSyncScenario(),
      Auth403PersistentPauseScenario(),
      Http415CompressionFallbackScenario(),
      OutageRecoveryDrainScenario(),
      HeadersRefreshOn401Scenario(),
      FlakyRetrySucceedsScenario(),
    ];
