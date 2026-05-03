import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:locus_example/harness/event_recorder.dart';
import 'package:locus_example/harness/recorded_event.dart';
import 'package:locus_example/mock_backend/mock_backend.dart';
import 'package:locus_example/scenarios/assertion_result.dart';
import 'package:locus_example/scenarios/scenario.dart';
import 'package:locus_example/scenarios/scenario_result.dart';
import 'package:locus_example/scenarios/scenario_runner.dart';

/// Detail screen for a single [Scenario]. Shows metadata, hosts the run
/// button, surfaces manual-step prompts as a banner with confirm/cancel
/// actions, and renders assertions + JSON export after completion.
class ScenarioDetailScreen extends StatefulWidget {
  const ScenarioDetailScreen({
    super.key,
    required this.scenario,
    required this.recorder,
    this.backend,
    this.previousResult,
  });

  /// Scenario to run on this screen. Immutable for the screen's lifetime.
  final Scenario scenario;

  /// Shared event recorder threaded into the runner.
  final EventRecorder recorder;

  /// Optional mock backend, threaded into the runner.
  final MockBackend? backend;

  /// Last known result for this scenario, if any. Lets the screen render
  /// the assertions and export button immediately on open without forcing
  /// a re-run.
  final ScenarioResult? previousResult;

  @override
  State<ScenarioDetailScreen> createState() => _ScenarioDetailScreenState();
}

class _ScenarioDetailScreenState extends State<ScenarioDetailScreen> {
  late ScenarioRunner _runner;

  bool _running = false;

  /// Outstanding manual-step prompt. Non-null while the runner is awaiting
  /// human acknowledgement. The completer is the bridge: tapping "I did it"
  /// completes it normally, "Cancel" completes with [ScenarioCancelled].
  String? _manualPrompt;
  Completer<void>? _manualCompleter;

  ScenarioResult? _result;

  @override
  void initState() {
    super.initState();
    _runner = ScenarioRunner(recorder: widget.recorder, backend: widget.backend);
    _result = widget.previousResult;
  }

  @override
  void dispose() {
    // If the user backs out mid-prompt, fail the pending manual step so the
    // runner unblocks instead of waiting forever.
    final Completer<void>? pending = _manualCompleter;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        const ScenarioCancelled('Detail screen disposed while awaiting manual step.'),
      );
    }
    _manualCompleter = null;
    super.dispose();
  }

  Future<void> _onManualStep(String prompt) {
    final Completer<void> completer = Completer<void>();
    setState(() {
      _manualPrompt = prompt;
      _manualCompleter = completer;
    });
    return completer.future;
  }

  void _confirmManualStep() {
    final Completer<void>? completer = _manualCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    widget.recorder.log(
      EventCategory.scenario,
      'manual_step_acknowledged',
      payload: <String, Object?>{
        'prompt': _manualPrompt ?? '',
        'scenarioId': widget.scenario.id,
      },
      sourceId: widget.scenario.id,
    );
    completer.complete();
    setState(() {
      _manualPrompt = null;
      _manualCompleter = null;
    });
  }

  void _cancelManualStep() {
    final Completer<void>? completer = _manualCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    widget.recorder.log(
      EventCategory.scenario,
      'manual_step_cancelled',
      payload: <String, Object?>{
        'prompt': _manualPrompt ?? '',
        'scenarioId': widget.scenario.id,
      },
      sourceId: widget.scenario.id,
    );
    completer.completeError(
      ScenarioCancelled('User cancelled manual step: ${_manualPrompt ?? ''}'),
    );
    setState(() {
      _manualPrompt = null;
      _manualCompleter = null;
    });
  }

  Future<void> _run() async {
    if (_running) {
      return;
    }
    setState(() {
      _running = true;
      _result = null;
    });

    final ScenarioResult result =
        await _runner.run(widget.scenario, onManualStep: _onManualStep);

    if (!mounted) {
      return;
    }
    setState(() {
      _running = false;
      _manualPrompt = null;
      _manualCompleter = null;
      _result = result;
    });
  }

  Future<void> _exportResult() async {
    final ScenarioResult? result = _result;
    if (result == null) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final Directory dir = Directory.systemTemp;
      final String stamp = result.finishedAt
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final File file = File('${dir.path}/scenario-${result.scenarioId}-$stamp.json');
      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(result.toJson()));
      messenger.showSnackBar(
        SnackBar(content: Text('Exported to ${file.path}')),
      );
    } on FileSystemException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Export failed: ${e.message}')),
      );
    }
  }

  /// Decides what to do when the system attempts to pop this route. We
  /// guard against mid-run pops (the runner has no cancellation hook, so
  /// letting the user leave would orphan the run) and otherwise pop with
  /// the latest [ScenarioResult] so the parent screen can refresh.
  void _handlePopAttempt() {
    if (_running) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scenario is still running.')),
      );
      return;
    }
    Navigator.of(context).pop(_result);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<ScenarioResult?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, ScenarioResult? _) {
        if (didPop) {
          return;
        }
        _handlePopAttempt();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.scenario.displayName),
        ),
        body: Column(
          children: <Widget>[
            if (_manualPrompt != null)
              _ManualStepBanner(
                prompt: _manualPrompt!,
                onConfirm: _confirmManualStep,
                onCancel: _cancelManualStep,
              ),
            if (_running) const LinearProgressIndicator(minHeight: 3),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  _MetadataSection(scenario: widget.scenario),
                  const SizedBox(height: 16),
                  _RunButton(
                    running: _running,
                    onPressed: _running ? null : _run,
                  ),
                  const SizedBox(height: 16),
                  if (_result != null) _ResultSection(result: _result!),
                  if (_result != null) ...<Widget>[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Export result'),
                      onPressed: _running ? null : _exportResult,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataSection extends StatelessWidget {
  const _MetadataSection({required this.scenario});

  final Scenario scenario;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(scenario.description, style: text.bodyMedium),
        const SizedBox(height: 12),
        _MetadataRow(label: 'ID', value: scenario.id),
        _MetadataRow(label: 'Category', value: scenario.category.name),
        _MetadataRow(
          label: 'Expected duration',
          value: _formatDuration(scenario.expectedDuration),
        ),
        _MetadataRow(
          label: 'Manual steps',
          value: scenario.requiresManualSteps ? 'required' : 'none',
        ),
        _MetadataRow(
          label: 'Mock backend',
          value: scenario.requiresMockBackend ? 'required' : 'not required',
        ),
      ],
    );
  }

  static String _formatDuration(Duration d) {
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

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _RunButton extends StatelessWidget {
  const _RunButton({required this.running, required this.onPressed});

  final bool running;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        icon: Icon(running ? Icons.hourglass_top : Icons.play_arrow),
        label: Text(running ? 'Running…' : 'Run'),
        onPressed: onPressed,
      ),
    );
  }
}

class _ManualStepBanner extends StatelessWidget {
  const _ManualStepBanner({
    required this.prompt,
    required this.onConfirm,
    required this.onCancel,
  });

  final String prompt;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.front_hand, color: scheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Manual step required',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    prompt,
                    style: TextStyle(color: scheme.onTertiaryContainer),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      FilledButton(
                        onPressed: onConfirm,
                        child: const Text('I did it'),
                      ),
                      OutlinedButton(
                        onPressed: onCancel,
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.result});

  final ScenarioResult result;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ResultHeader(result: result),
        const SizedBox(height: 12),
        if (result.error != null)
          _ErrorPanel(
            error: result.error!,
            phase: result.errorPhase ?? 'unknown',
          ),
        if (result.assertions.isEmpty)
          Text(
            'No assertions ran.',
            style: text.bodySmall,
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Assertions', style: text.titleSmall),
              const SizedBox(height: 8),
              for (final AssertionResult a in result.assertions)
                _AssertionRow(assertion: a),
            ],
          ),
      ],
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({required this.result});

  final ScenarioResult result;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final (IconData icon, Color color, String label) = _present(result.status);
    return Row(
      children: <Widget>[
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: text.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${result.passedCount} passed · ${result.failedCount} failed · '
                '${result.skippedCount} skipped · ${result.duration.inMilliseconds}ms',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static (IconData, Color, String) _present(ScenarioRunStatus status) {
    switch (status) {
      case ScenarioRunStatus.passed:
        return (Icons.check_circle, Colors.green, 'Passed');
      case ScenarioRunStatus.failed:
        return (Icons.cancel, Colors.red, 'Failed');
      case ScenarioRunStatus.errored:
        return (Icons.error, Colors.orange, 'Errored');
      case ScenarioRunStatus.cancelled:
        return (Icons.block, Colors.grey, 'Cancelled');
    }
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.phase});

  final String error;
  final String phase;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Error during $phase',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: scheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            error,
            style: TextStyle(color: scheme.onErrorContainer),
          ),
        ],
      ),
    );
  }
}

class _AssertionRow extends StatefulWidget {
  const _AssertionRow({required this.assertion});

  final AssertionResult assertion;

  @override
  State<_AssertionRow> createState() => _AssertionRowState();
}

class _AssertionRowState extends State<_AssertionRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final AssertionResult a = widget.assertion;
    final (IconData icon, Color color) = _iconFor(a.status);
    final bool hasDetail = a.failureDetail != null ||
        a.expected != null ||
        a.actual != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: hasDetail
                ? () => setState(() => _expanded = !_expanded)
                : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    a.description,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (hasDetail)
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
              ],
            ),
          ),
          if (_expanded && hasDetail)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 4, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (a.failureDetail != null)
                    _DetailLine(label: 'Detail', value: a.failureDetail!),
                  if (a.expected != null)
                    _DetailLine(label: 'Expected', value: a.expected.toString()),
                  if (a.actual != null)
                    _DetailLine(label: 'Actual', value: a.actual.toString()),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static (IconData, Color) _iconFor(AssertionStatus status) {
    switch (status) {
      case AssertionStatus.pass:
        return (Icons.check_circle, Colors.green);
      case AssertionStatus.fail:
        return (Icons.cancel, Colors.red);
      case AssertionStatus.skip:
        return (Icons.remove_circle_outline, Colors.grey);
    }
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12, color: scheme.onSurface),
          children: <InlineSpan>[
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
