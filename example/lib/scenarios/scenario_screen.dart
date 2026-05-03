import 'package:flutter/material.dart';
import 'package:locus_example/harness/event_recorder.dart';
import 'package:locus_example/mock_backend/mock_backend.dart';
import 'package:locus_example/scenarios/scenario.dart';
import 'package:locus_example/scenarios/scenario_detail_screen.dart';
import 'package:locus_example/scenarios/scenario_result.dart';

/// Top-level "Scenarios" tab screen. Lists every registered [Scenario] with
/// its category, expected duration, manual-step requirement and last-run
/// status, and routes into [ScenarioDetailScreen] for execution.
class ScenarioScreen extends StatefulWidget {
  const ScenarioScreen({
    super.key,
    required this.recorder,
    required this.scenarios,
    this.backend,
  });

  /// Shared event recorder. Forwarded to the runner inside
  /// [ScenarioDetailScreen]; the list screen itself does not consume events.
  final EventRecorder recorder;

  /// Optional mock backend, threaded through to scenarios that need it.
  final MockBackend? backend;

  /// Scenarios to display. The screen never mutates this list — to refresh
  /// the catalog, the caller can rebuild the screen.
  final List<Scenario> scenarios;

  @override
  State<ScenarioScreen> createState() => _ScenarioScreenState();
}

class _ScenarioScreenState extends State<ScenarioScreen> {
  /// Last [ScenarioResult] keyed by [Scenario.id]. We keep it on the parent
  /// so the list survives navigation back from the detail screen.
  final Map<String, ScenarioResult> _lastResults = <String, ScenarioResult>{};

  /// Local copy of the scenarios list. Refreshed by the AppBar action so
  /// hot-reloaded catalog edits are visible without a full app restart.
  late List<Scenario> _scenarios;

  @override
  void initState() {
    super.initState();
    _scenarios = List<Scenario>.unmodifiable(widget.scenarios);
  }

  @override
  void didUpdateWidget(covariant ScenarioScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.scenarios, widget.scenarios)) {
      _scenarios = List<Scenario>.unmodifiable(widget.scenarios);
    }
  }

  void _refreshCatalog() {
    setState(() {
      _scenarios = List<Scenario>.unmodifiable(widget.scenarios);
    });
  }

  Future<void> _openDetail(Scenario scenario) async {
    final ScenarioResult? result = await Navigator.of(context).push(
      MaterialPageRoute<ScenarioResult>(
        builder: (BuildContext context) => ScenarioDetailScreen(
          scenario: scenario,
          recorder: widget.recorder,
          backend: widget.backend,
          previousResult: _lastResults[scenario.id],
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    setState(() {
      _lastResults[result.scenarioId] = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scenarios'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh catalog',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshCatalog,
          ),
        ],
      ),
      body: _scenarios.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _scenarios.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final Scenario scenario = _scenarios[index];
                return _ScenarioTile(
                  scenario: scenario,
                  lastResult: _lastResults[scenario.id],
                  onTap: () => _openDetail(scenario),
                );
              },
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.science_outlined, size: 48),
            const SizedBox(height: 12),
            Text('No scenarios registered.', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Add a scenario to the catalog and refresh.',
              style: text.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the scenarios list.
class _ScenarioTile extends StatelessWidget {
  const _ScenarioTile({
    required this.scenario,
    required this.lastResult,
    required this.onTap,
  });

  final Scenario scenario;
  final ScenarioResult? lastResult;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return ListTile(
      onTap: onTap,
      title: Text(scenario.displayName, style: text.titleMedium),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _CategoryChip(category: scenario.category),
            _DurationChip(duration: scenario.expectedDuration),
            if (scenario.requiresManualSteps) const _ManualStepsChip(),
            if (scenario.requiresMockBackend) const _MockBackendChip(),
          ],
        ),
      ),
      trailing: _StatusBadge(result: lastResult),
      isThreeLine: true,
    );
  }
}

/// Coloured chip for [ScenarioCategory].
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});

  final ScenarioCategory category;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = _colorFor(category, scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        _labelFor(category),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  static String _labelFor(ScenarioCategory category) {
    switch (category) {
      case ScenarioCategory.lifecycle:
        return 'lifecycle';
      case ScenarioCategory.sync:
        return 'sync';
      case ScenarioCategory.httpAdversarial:
        return 'http';
      case ScenarioCategory.geofencing:
        return 'geofencing';
      case ScenarioCategory.battery:
        return 'battery';
    }
  }

  static Color _colorFor(ScenarioCategory category, ColorScheme scheme) {
    switch (category) {
      case ScenarioCategory.lifecycle:
        return scheme.primary;
      case ScenarioCategory.sync:
        return scheme.tertiary;
      case ScenarioCategory.httpAdversarial:
        return scheme.error;
      case ScenarioCategory.geofencing:
        return scheme.secondary;
      case ScenarioCategory.battery:
        return Colors.orange.shade700;
    }
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.schedule, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          _format(duration),
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  static String _format(Duration d) {
    if (d.inMinutes >= 1) {
      final int seconds = d.inSeconds % 60;
      if (seconds == 0) {
        return '${d.inMinutes}m';
      }
      return '${d.inMinutes}m ${seconds}s';
    }
    return '${d.inSeconds}s';
  }
}

class _ManualStepsChip extends StatelessWidget {
  const _ManualStepsChip();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Requires manual interaction',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.touch_app, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            'manual',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MockBackendChip extends StatelessWidget {
  const _MockBackendChip();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Requires mock backend',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.cloud_outlined,
              size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            'mock',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact badge summarising the previous run status.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.result});

  final ScenarioResult? result;

  @override
  Widget build(BuildContext context) {
    final ScenarioResult? r = result;
    if (r == null) {
      return const Icon(Icons.chevron_right);
    }
    final (IconData icon, Color color, String label) = _present(r.status);
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  static (IconData, Color, String) _present(ScenarioRunStatus status) {
    switch (status) {
      case ScenarioRunStatus.passed:
        return (Icons.check_circle, Colors.green, 'pass');
      case ScenarioRunStatus.failed:
        return (Icons.cancel, Colors.red, 'fail');
      case ScenarioRunStatus.errored:
        return (Icons.error, Colors.orange, 'error');
      case ScenarioRunStatus.cancelled:
        return (Icons.block, Colors.grey, 'cancel');
    }
  }
}
