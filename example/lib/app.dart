import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:locus_example/demos/demos_screen.dart';
import 'package:locus_example/harness/event_log_screen.dart';
import 'package:locus_example/harness/event_recorder.dart';
import 'package:locus_example/harness/event_recorder_impl.dart';
import 'package:locus_example/mock_backend/mock_backend.dart';
import 'package:locus_example/mock_backend/mock_backend_impl.dart';
import 'package:locus_example/mock_backend/mock_backend_screen.dart';
import 'package:locus_example/scenarios/catalog/phase1_scenarios.dart';
import 'package:locus_example/scenarios/catalog/phase2_scenarios.dart';
import 'package:locus_example/scenarios/scenario.dart';
import 'package:locus_example/scenarios/scenario_screen.dart';

/// Root widget for the Locus example application.
///
/// Owns the lifetime of the singleton harness primitives — the
/// [EventRecorder] and the [HttpMockBackend] — by construction in
/// [State.initState] and disposal in [State.dispose]. While those are
/// asynchronously coming up, the app shows a small splash so child screens
/// never receive a half-initialised harness.
class LocusExampleApp extends StatefulWidget {
  const LocusExampleApp({super.key});

  @override
  State<LocusExampleApp> createState() => _LocusExampleAppState();
}

class _LocusExampleAppState extends State<LocusExampleApp> {
  late final DefaultEventRecorder _recorder;
  HttpMockBackend? _backend;
  String? _backendError;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _recorder = DefaultEventRecorder();
    unawaited(_initialise());
  }

  Future<void> _initialise() async {
    await _recorder.start();
    try {
      _backend = await HttpMockBackend.start();
    } on Object catch (error) {
      // Failing to bind the mock backend is non-fatal: the demos and Phase 1
      // scenarios still work without it. Surface the failure on the Mock
      // Backend tab instead of crashing the app.
      _backendError = error.toString();
    }
    if (!mounted) return;
    setState(() => _initialized = true);
  }

  @override
  void dispose() {
    // Order matters: cancel SDK subscriptions before tearing down the HTTP
    // server so any in-flight events the SDK emits during shutdown still go
    // somewhere sane.
    unawaitedDispose(_recorder);
    if (_backend != null) {
      unawaitedDispose(_backend!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Locus Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E5D4B),
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.interTextTheme(),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
      ),
      home: _initialized
          ? _RootScaffold(
              recorder: _recorder,
              backend: _backend,
              backendError: _backendError,
              scenarios: <Scenario>[
                ...phase1Scenarios(),
                ...phase2Scenarios(),
              ],
            )
          : const _BootSplash(),
    );
  }
}

/// Fire-and-forget dispose. We can't `await` from [State.dispose], so the
/// returned future is intentionally dropped — the harness `dispose()` only
/// schedules cleanup work that is safe to run asynchronously after this
/// frame returns.
void unawaitedDispose(Object disposable) {
  if (disposable is EventRecorder) {
    unawaited(disposable.dispose());
  } else if (disposable is MockBackend) {
    unawaited(disposable.dispose());
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Booting harness…'),
          ],
        ),
      ),
    );
  }
}

class _RootScaffold extends StatelessWidget {
  const _RootScaffold({
    required this.recorder,
    required this.scenarios,
    this.backend,
    this.backendError,
  });

  final EventRecorder recorder;
  final MockBackend? backend;
  final String? backendError;
  final List<Scenario> scenarios;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        appBar: AppBar(
          title: Row(
            children: <Widget>[
              SvgPicture.asset(
                'assets/locus_logo.svg',
                width: 32,
                height: 32,
              ),
              const SizedBox(width: 10),
              const Text(
                'Locus',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: <Widget>[
            IconButton(
              tooltip: 'Open event log',
              icon: const Icon(Icons.history),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext _) =>
                      EventLogScreen(recorder: recorder),
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(icon: Icon(Icons.dashboard_rounded), text: 'Demos'),
              Tab(icon: Icon(Icons.science_rounded), text: 'Scenarios'),
              Tab(icon: Icon(Icons.cloud_outlined), text: 'Mock Backend'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            const DemosScreen(),
            ScenarioScreen(
              recorder: recorder,
              backend: backend,
              scenarios: scenarios,
            ),
            backend != null
                ? MockBackendScreen(backend: backend!)
                : _BackendUnavailableNotice(error: backendError),
          ],
        ),
      ),
    );
  }
}

class _BackendUnavailableNotice extends StatelessWidget {
  const _BackendUnavailableNotice({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.cloud_off_outlined, color: scheme.error, size: 36),
          const SizedBox(height: 8),
          Text(
            'Mock backend failed to start',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Phase 2 scenarios cannot run until the in-process mock HTTP '
            'server binds to a local port. Phase 1 scenarios and the '
            'Demos tab are unaffected.',
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              error!,
              style: TextStyle(
                fontFamily: 'monospace',
                color: scheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
