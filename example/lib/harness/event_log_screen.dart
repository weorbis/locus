/// In-app event log viewer.
///
/// Renders the harness's [EventRecorder] state as a scrollable, filterable,
/// exportable list. Lives in the example app navigator at a stable route so
/// scenarios can deep-link to it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:locus_example/harness/event_log_exporter.dart';
import 'package:locus_example/harness/event_recorder.dart';
import 'package:locus_example/harness/recorded_event.dart';

/// Top-level screen presenting the recorder's contents.
///
/// Stateless on purpose: the per-screen filter selection is owned by the
/// private [_EventLogBody] state object, the event list is owned by the
/// recorder, and we let `AnimatedBuilder(animation: recorder, ...)` push
/// updates without leaning on `setState` from this widget.
class EventLogScreen extends StatelessWidget {
  /// Builds an event-log screen bound to [recorder].
  const EventLogScreen({required this.recorder, super.key});

  /// The shared recorder instance — usually the singleton constructed at
  /// app entry. The screen does not own its lifecycle.
  final EventRecorder recorder;

  @override
  Widget build(BuildContext context) {
    return _EventLogBody(recorder: recorder);
  }
}

// ---------------------------------------------------------------------------
// Private state holder for filter selection. The spec caps the *visible*
// widgets at two (screen + tile); this private stateful wrapper exists only
// to anchor the filter panel's local state and is intentionally inline.
// ---------------------------------------------------------------------------

class _EventLogBody extends StatefulWidget {
  const _EventLogBody({required this.recorder});

  final EventRecorder recorder;

  @override
  State<_EventLogBody> createState() => _EventLogBodyState();
}

class _EventLogBodyState extends State<_EventLogBody> {
  /// Selected categories. Empty => "show everything"; treating empty as
  /// "show none" would silently hide all entries the moment a user opened
  /// the filter sheet without picking anything.
  final Set<EventCategory> _selected = <EventCategory>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Log'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Filter',
            icon: const Icon(Icons.filter_list),
            onPressed: _openFilterSheet,
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: _confirmClear,
          ),
          IconButton(
            tooltip: 'Export',
            icon: const Icon(Icons.ios_share),
            onPressed: _export,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: widget.recorder,
        builder: (BuildContext context, Widget? _) => _buildList(context),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Body
  // ---------------------------------------------------------------------------

  Widget _buildList(BuildContext context) {
    final visible = _filtered(widget.recorder.events);
    if (visible.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'No events yet — run a scenario to see entries here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Newest first. Build via reverse-index lookups so we don't allocate
    // a reversed copy of the list on every rebuild.
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (BuildContext context, int index) {
        final event = visible[visible.length - 1 - index];
        return _EventTile(
          event: event,
          onTap: () => _showEventDetails(context, event),
        );
      },
    );
  }

  List<RecordedEvent> _filtered(List<RecordedEvent> source) {
    if (_selected.isEmpty) return source;
    final out = <RecordedEvent>[];
    for (final event in source) {
      if (_selected.contains(event.category)) out.add(event);
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // App-bar actions
  // ---------------------------------------------------------------------------

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<Set<EventCategory>>(
      context: context,
      builder: (BuildContext sheetContext) => _FilterSheet(
        initial: _selected,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _selected
        ..clear()
        ..addAll(result);
    });
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Clear event log?'),
        content: const Text(
          'This removes all currently recorded events. The recorder will '
          'continue capturing new events as they arrive.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    widget.recorder.clear();
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    final events = widget.recorder.events;
    if (events.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nothing to export — log is empty.')),
      );
      return;
    }
    try {
      final dir = Directory.systemTemp;
      final file = await EventLogExporter.writeJson(
        events,
        directory: dir,
        filenamePrefix: 'locus-event-log',
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Exported ${events.length} events to ${file.path}'),
          duration: const Duration(seconds: 6),
        ),
      );
    } on FileSystemException catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Export failed: ${error.message}')),
      );
    } on ArgumentError catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Export failed: ${error.message}')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Detail sheet — shows the full JSON payload for a tapped event.
  // ---------------------------------------------------------------------------

  Future<void> _showEventDetails(
    BuildContext context,
    RecordedEvent event,
  ) async {
    final pretty =
        const JsonEncoder.withIndent('  ').convert(event.toJson());
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          builder: (BuildContext _, ScrollController controller) => Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              controller: controller,
              child: SelectableText(
                pretty,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Filter sheet (private widget, not counted toward the screen budget — it is
// purely a transient modal builder).
// ---------------------------------------------------------------------------

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});

  final Set<EventCategory> initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final Set<EventCategory> _draft = <EventCategory>{...widget.initial};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Filter by category',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            for (final category in EventCategory.values)
              CheckboxListTile(
                value: _draft.contains(category),
                title: Text(_categoryLabel(category)),
                onChanged: (bool? checked) => setState(() {
                  if (checked ?? false) {
                    _draft.add(category);
                  } else {
                    _draft.remove(category);
                  }
                }),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  TextButton(
                    onPressed: () => setState(_draft.clear),
                    child: const Text('Clear'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_draft),
                    child: const Text('Apply'),
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

// ---------------------------------------------------------------------------
// Tile — second of the two visible widgets the screen owns.
// ---------------------------------------------------------------------------

/// Compact list tile rendering one [RecordedEvent].
///
/// Kept deliberately stateless and `const`-friendly — long event logs need
/// fast list-item rebuild — so children are wrapped in `const` widgets
/// where possible.
class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.onTap});

  final RecordedEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = _formatTimeOfDay(event.at);
    final subtitle = _payloadPreview(event.payload);
    return ListTile(
      onTap: onTap,
      dense: true,
      leading: _CategoryBadge(category: event.category),
      title: Row(
        children: <Widget>[
          Text(time, style: const TextStyle(fontFamily: 'monospace')),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              event.type,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
    );
  }

  static String _formatTimeOfDay(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}.'
        '${three(at.millisecond)}';
  }

  static String _payloadPreview(Map<String, Object?> payload) {
    if (payload.isEmpty) return '';
    final flat = payload.entries
        .map((MapEntry<String, Object?> entry) =>
            '${entry.key}=${entry.value}')
        .join(' ');
    if (flat.length <= 80) return flat;
    return '${flat.substring(0, 80)}…';
  }
}

// ---------------------------------------------------------------------------
// Category badge — small visual helper, not a user-facing widget. Kept
// inline to avoid bloating the file count and to keep colour decisions
// adjacent to the screen they apply to.
// ---------------------------------------------------------------------------

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category});

  final EventCategory category;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(category);
    return Container(
      width: 8,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.all(Radius.circular(2)),
      ),
    );
  }

  static Color _colorFor(EventCategory category) {
    switch (category) {
      case EventCategory.location:
        return const Color(0xFF2E7D32); // green
      case EventCategory.geofence:
        return const Color(0xFF1565C0); // blue
      case EventCategory.sync:
        return const Color(0xFF6A1B9A); // purple
      case EventCategory.http:
        return const Color(0xFFE65100); // orange
      case EventCategory.lifecycle:
        return const Color(0xFF455A64); // blue-grey
      case EventCategory.error:
        return const Color(0xFFC62828); // red
      case EventCategory.scenario:
        return const Color(0xFF00838F); // teal
    }
  }
}

String _categoryLabel(EventCategory category) {
  switch (category) {
    case EventCategory.location:
      return 'Location';
    case EventCategory.geofence:
      return 'Geofence';
    case EventCategory.sync:
      return 'Sync';
    case EventCategory.http:
      return 'HTTP';
    case EventCategory.lifecycle:
      return 'Lifecycle';
    case EventCategory.error:
      return 'Error';
    case EventCategory.scenario:
      return 'Scenario';
  }
}
