import 'package:flutter/material.dart';
import 'package:locus/locus.dart';

/// A bounded native history query, with a fixed time window across its pages.
class StoredLocationsCard extends StatefulWidget {
  const StoredLocationsCard({super.key, required this.onClear, this.query});

  final Future<void> Function() onClear;
  final Future<List<Location>> Function(LocationQuery)? query;

  @override
  State<StoredLocationsCard> createState() => _StoredLocationsCardState();
}

class _StoredLocationsCardState extends State<StoredLocationsCard> {
  final _form = GlobalKey<FormState>();
  final _boundsExpansion = ExpansibleController();
  final _accuracy = TextEditingController();
  final _south = TextEditingController();
  final _west = TextEditingController();
  final _north = TextEditingController();
  final _east = TextEditingController();
  int _hours = 0;
  int _pageSize = 10;
  LocationSortOrder _order = LocationSortOrder.newestFirst;
  bool? _moving;
  bool _useBounds = false;
  bool _invalidQuery = false;
  bool _busy = false;
  bool _hasNext = false;
  int _request = 0;
  int _offset = 0;
  LocationQuery? _applied;
  List<Location>? _rows;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_accuracy, _south, _west, _north, _east]) {
      controller.dispose();
    }
    _boundsExpansion.dispose();
    super.dispose();
  }

  void _changed(VoidCallback change) {
    setState(() {
      change();
      _invalidQuery = false;
      _request++;
      _busy = false;
      _offset = 0;
      _applied = null;
      _resetResults();
    });
  }

  void _resetResults() {
    _rows = null;
    _error = null;
    _hasNext = false;
  }

  String? _number(String? value, double min, double max) {
    final number = double.tryParse(value?.trim() ?? '');
    if (number == null || !number.isFinite || number < min || number > max) {
      return 'Enter a number from $min to $max';
    }
    return null;
  }

  Future<void> _apply() async {
    if (!_form.currentState!.validate()) {
      if (_useBounds) _boundsExpansion.expand();
      setState(() => _invalidQuery = true);
      return;
    }
    _invalidQuery = false;
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    _applied = LocationQuery(
      from: _hours == 0 ? null : now.subtract(Duration(hours: _hours)),
      to: now,
      sortOrder: _order,
      isMoving: _moving,
      // The SDK's historical minAccuracy name means accuracy <= this value.
      minAccuracy: double.tryParse(_accuracy.text.trim()),
      bounds: _useBounds
          ? LocationBounds(
              southwest: Coords(
                latitude: double.parse(_south.text),
                longitude: double.parse(_west.text),
                accuracy: 0,
              ),
              northeast: Coords(
                latitude: double.parse(_north.text),
                longitude: double.parse(_east.text),
                accuracy: 0,
              ),
            )
          : null,
    );
    await _load(0);
  }

  Future<void> _load(int offset) async {
    final applied = _applied;
    if (applied == null) return;
    final request = ++_request;
    final pageSize = _pageSize;
    setState(() {
      _busy = true;
      _offset = offset;
      _resetResults();
    });
    try {
      final rows = await (widget.query ?? Locus.location.query)(
        LocationQuery(
          from: applied.from,
          to: applied.to,
          minAccuracy: applied.minAccuracy,
          isMoving: applied.isMoving,
          bounds: applied.bounds,
          sortOrder: applied.sortOrder,
          offset: offset,
          // One bounded look-ahead record tells us if another page exists.
          limit: pageSize + 1,
        ),
      );
      if (!mounted || request != _request) return;
      setState(() {
        _rows = rows.take(pageSize).toList();
        _hasNext = rows.length > pageSize;
        _busy = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = 'Could not load history: $error';
        _busy = false;
      });
    }
  }

  Future<void> _clear() async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _applied = null;
      _offset = 0;
      _resetResults();
    });
    try {
      await widget.onClear();
      if (!mounted || request != _request) return;
      setState(() {
        _busy = false;
        _rows = const [];
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _busy = false;
        _error = 'Could not clear all locations: $error';
      });
    }
  }

  Widget _field(
    String label,
    TextEditingController controller,
    String? Function(String?) validate,
  ) => TextFormField(
    controller: controller,
    enabled: !_busy,
    keyboardType: const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    ),
    decoration: InputDecoration(labelText: label),
    validator: validate,
    onChanged: (_) => _changed(() {}),
  );

  Widget _select<T>(
    String label,
    T value,
    Map<T, String> options,
    ValueChanged<T> change,
  ) => DropdownButtonFormField<T>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: options.entries
        .map(
          (entry) =>
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        )
        .toList(),
    onChanged: _busy
        ? null
        : (selected) {
            if (selected != null) _changed(() => change(selected));
          },
  );

  @override
  Widget build(BuildContext context) {
    final page = _offset ~/ _pageSize + 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Not SectionHeader: this title must wrap on narrow screens.
              Row(
                children: [
                  Icon(
                    Icons.storage_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Stored Locations',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Query stored history in bounded pages. Apply filters to start a new fixed time window.',
              ),
              const SizedBox(height: 12),
              _select('Time range', _hours, const {
                0: 'All history',
                1: 'Last hour',
                24: 'Last day',
                168: 'Last week',
              }, (value) => _hours = value),
              _select('Order', _order, const {
                LocationSortOrder.newestFirst: 'Newest first',
                LocationSortOrder.oldestFirst: 'Oldest first',
              }, (value) => _order = value),
              _select(
                'Motion',
                _moving == null ? 'all' : (_moving! ? 'moving' : 'stationary'),
                const {
                  'all': 'All motion',
                  'moving': 'Moving',
                  'stationary': 'Stationary',
                },
                (value) => _moving = value == 'all' ? null : value == 'moving',
              ),
              _select('Page size', _pageSize, const {
                10: '10 locations',
                25: '25 locations',
                50: '50 locations',
              }, (value) => _pageSize = value),
              _field('Accuracy limit (meters, optional)', _accuracy, (value) {
                if (value == null || value.trim().isEmpty) return null;
                final number = double.tryParse(value.trim());
                return number == null || !number.isFinite || number < 0
                    ? 'Enter a finite number of meters, 0 or greater'
                    : null;
              }),
              const SizedBox(height: 6),
              const Text(
                'Include accuracy ≤ this limit. Lower values mean more precise locations.',
              ),
              ExpansionTile(
                controller: _boundsExpansion,
                maintainState: true,
                tilePadding: EdgeInsets.zero,
                title: const Text('Geographic bounds (optional)'),
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Filter by bounds'),
                    value: _useBounds,
                    onChanged: _busy
                        ? null
                        : (value) => _changed(() => _useBounds = value),
                  ),
                  if (_useBounds) ...[
                    const Text(
                      'Inclusive ranges. South ≤ north and west ≤ east; no longitude wrapping.',
                    ),
                    _field(
                      'South latitude',
                      _south,
                      (value) => _number(value, -90, 90),
                    ),
                    _field('North latitude', _north, (value) {
                      final error = _number(value, -90, 90);
                      if (error != null) return error;
                      final south = double.tryParse(_south.text);
                      return south != null && double.parse(value!) < south
                          ? 'North must be at least south'
                          : null;
                    }),
                    _field(
                      'West longitude',
                      _west,
                      (value) => _number(value, -180, 180),
                    ),
                    _field('East longitude', _east, (value) {
                      final error = _number(value, -180, 180);
                      if (error != null) return error;
                      final west = double.tryParse(_west.text);
                      return west != null && double.parse(value!) < west
                          ? 'East must be at least west'
                          : null;
                    }),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _apply,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Apply query'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _clear,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Clear all stored locations'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Clear all removes every stored location, including those outside this query.',
              ),
              if (_invalidQuery)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    'Check the highlighted fields before applying the query.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(
                  semanticsLabel: 'Loading stored locations',
                ),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _applied == null ? _clear : () => _load(_offset),
                  child: const Text('Retry'),
                ),
              ],
              if (_applied != null) ...[
                const SizedBox(height: 12),
                Text('Window ends ${_applied!.to!.toLocal()}'),
                Text(
                  '${_busy ? 'Loading page' : 'Page'} $page',
                  semanticsLabel: 'History page $page',
                ),
              ],
              if (_rows case final rows?) ...[
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No stored locations match. Adjust filters or record some locations.',
                    ),
                  ),
                for (final (index, location) in rows.indexed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${_offset + index + 1}. ${location.coords.latitude.toStringAsFixed(5)}, ${location.coords.longitude.toStringAsFixed(5)}',
                    ),
                    subtitle: Text(
                      '${location.timestamp.toLocal()}\nAccuracy ${location.coords.accuracy.toStringAsFixed(0)} m',
                    ),
                    isThreeLine: true,
                  ),
              ],
              Wrap(
                spacing: 12,
                children: [
                  TextButton.icon(
                    onPressed: !_busy && _error == null && _offset > 0
                        ? () => _load(_offset - _pageSize)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Previous page'),
                  ),
                  TextButton.icon(
                    onPressed: !_busy && _error == null && _hasNext
                        ? () => _load(_offset + _pageSize)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Next page'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
