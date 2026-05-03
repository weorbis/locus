import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:locus_example/mock_backend/mock_backend.dart';

/// How often the request list refreshes. The mock has no change-notification
/// hook, so we poll. 1 Hz is fast enough for human inspection during a
/// scenario run and cheap enough to leave running indefinitely.
const Duration _kRefreshInterval = Duration(seconds: 1);

/// Maximum bytes of a captured request body to render in the inspector. Above
/// this, the preview is truncated with a notice — the full bytes remain on
/// the [MockRequest].
const int _kBodyPreviewByteLimit = 4096;

/// Diagnostics screen for an attached [MockBackend]. Shows the active mode,
/// the base URL, the running request count, and a tail of recent requests.
///
/// The screen does not own the backend — it observes one passed in. The
/// caller is responsible for [MockBackend.dispose].
class MockBackendScreen extends StatefulWidget {
  const MockBackendScreen({
    required this.backend,
    super.key,
  });

  final MockBackend backend;

  @override
  State<MockBackendScreen> createState() => _MockBackendScreenState();
}

class _MockBackendScreenState extends State<MockBackendScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(_kRefreshInterval, (_) {
      if (!mounted) return;
      setState(() {
        // The backend mutates its own buffers; rebuild to re-read them.
      });
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    super.dispose();
  }

  Future<void> _onModeChanged(MockMode? next) async {
    if (next == null || next == widget.backend.mode) return;
    await widget.backend.setMode(next);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _onReset() async {
    await widget.backend.reset();
    if (!mounted) return;
    setState(() {});
    final ScaffoldMessengerState? messenger =
        ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Mock backend reset')),
    );
  }

  Future<void> _copyBaseUrl() async {
    await Clipboard.setData(
      ClipboardData(text: widget.backend.baseUrl.toString()),
    );
    if (!mounted) return;
    final ScaffoldMessengerState? messenger =
        ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Copied base URL')),
    );
  }

  void _showRequestDetails(MockRequest req) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (BuildContext ctx) => _RequestDetailsSheet(request: req),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final MockBackend backend = widget.backend;
    final List<MockRequest> requests = backend.recentRequests;

    return Scaffold(
      appBar: AppBar(title: const Text('Mock Backend')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: <Widget>[
          _BaseUrlCard(
            url: backend.baseUrl,
            onCopy: _copyBaseUrl,
          ),
          const SizedBox(height: 16),
          _ModePicker(
            current: backend.mode,
            onChanged: _onModeChanged,
          ),
          const SizedBox(height: 16),
          _CountRow(
            count: backend.requestCount,
            onReset: _onReset,
          ),
          const SizedBox(height: 16),
          _RecentRequestsHeader(visible: requests.length, total: requests.length),
          const SizedBox(height: 8),
          if (requests.isEmpty)
            const _EmptyRequestsHint()
          else
            for (final MockRequest r in requests)
              _RequestTile(
                key: ValueKey<String>(
                  '${r.at.microsecondsSinceEpoch}-${r.path}',
                ),
                request: r,
                onTap: () => _showRequestDetails(r),
              ),
        ],
      ),
    );
  }
}

// =============================================================================
// Sub-widgets
// =============================================================================

class _BaseUrlCard extends StatelessWidget {
  const _BaseUrlCard({required this.url, required this.onCopy});

  final Uri url;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Base URL', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  SelectableText(
                    url.toString(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Copy base URL',
              icon: const Icon(Icons.copy),
              onPressed: onCopy,
            ),
          ],
        ),
      ),
    );
  }
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.current, required this.onChanged});

  final MockMode current;
  final ValueChanged<MockMode?> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: RadioGroup<MockMode>(
          groupValue: current,
          onChanged: onChanged,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Mode', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              for (final MockMode m in MockMode.values)
                RadioListTile<MockMode>(
                  title: Text(_modeLabel(m)),
                  subtitle: Text(
                    _modeDescription(m),
                    style: theme.textTheme.bodySmall,
                  ),
                  value: m,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _modeLabel(MockMode m) {
    switch (m) {
      case MockMode.normal:
        return 'Normal (200)';
      case MockMode.auth401:
        return 'Auth 401';
      case MockMode.auth403:
        return 'Auth 403';
      case MockMode.http415Once:
        return '415 once';
      case MockMode.slow:
        return 'Slow';
      case MockMode.drop:
        return 'Drop connection';
      case MockMode.flaky:
        return 'Flaky (alternating 500/200)';
      case MockMode.outage:
        return 'Outage (503 then 200)';
    }
  }

  static String _modeDescription(MockMode m) {
    switch (m) {
      case MockMode.normal:
        return 'Always returns 200 OK with an empty JSON body.';
      case MockMode.auth401:
        return 'Returns 401 Unauthorized; exercises auth-pause.';
      case MockMode.auth403:
        return 'Returns 403 Forbidden; exercises auth-pause persistence.';
      case MockMode.http415Once:
        return 'First request 415, subsequent 200 — compression fallback.';
      case MockMode.slow:
        return 'Delays response (default 5s) to test read timeouts.';
      case MockMode.drop:
        return 'Closes the TCP socket with no HTTP response.';
      case MockMode.flaky:
        return '1st/3rd/… requests 500, 2nd/4th/… succeed.';
      case MockMode.outage:
        return 'First N (default 5) requests 503, then 200.';
    }
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.count, required this.onReset});

  final int count;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Requests', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 2),
                  Text(
                    '$count',
                    style: theme.textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentRequestsHeader extends StatelessWidget {
  const _RecentRequestsHeader({required this.visible, required this.total});

  final int visible;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: <Widget>[
          Text(
            'Recent requests',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Spacer(),
          Text(
            visible == total ? '$visible' : '$visible / $total',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _EmptyRequestsHint extends StatelessWidget {
  const _EmptyRequestsHint();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'No requests captured yet.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.onTap,
    super.key,
  });

  final MockRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: _StatusBadge(status: request.responseStatus),
        title: Text(
          '${request.method} ${request.path.isEmpty ? '/' : request.path}',
          style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace'),
        ),
        subtitle: Text(
          '${_formatTime(request.at)}  ·  ${request.bodyBytes.length} B'
          '${request.isGzipped ? '  ·  gzip' : ''}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  static String _formatTime(DateTime at) {
    final DateTime local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}'
        '.${three(local.millisecond)}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final int status;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    if (status == 0) {
      bg = Colors.grey.shade400;
      fg = Colors.black87;
    } else if (status >= 200 && status < 300) {
      bg = Colors.green.shade600;
      fg = Colors.white;
    } else if (status >= 400 && status < 500) {
      bg = Colors.amber.shade700;
      fg = Colors.black87;
    } else if (status >= 500) {
      bg = Colors.red.shade600;
      fg = Colors.white;
    } else {
      bg = Colors.blueGrey.shade400;
      fg = Colors.white;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status == 0 ? '—' : '$status',
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// =============================================================================
// Bottom sheet — request details
// =============================================================================

class _RequestDetailsSheet extends StatelessWidget {
  const _RequestDetailsSheet({required this.request});

  final MockRequest request;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MediaQueryData media = MediaQuery.of(context);
    final List<MapEntry<String, String>> headers = request.headers.entries
        .toList(growable: false)
      ..sort((MapEntry<String, String> a, MapEntry<String, String> b) =>
          a.key.compareTo(b.key));

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + media.viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _StatusBadge(status: request.responseStatus),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${request.method} ${request.path.isEmpty ? '/' : request.path}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              request.at.toLocal().toIso8601String(),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text('Headers', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (headers.isEmpty)
                      Text(
                        '(none)',
                        style: theme.textTheme.bodySmall,
                      )
                    else
                      for (final MapEntry<String, String> h in headers)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: SelectableText(
                            '${h.key}: ${h.value}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                        ),
                    const SizedBox(height: 16),
                    Text(
                      'Body (${request.bodyBytes.length} bytes'
                      '${request.isGzipped ? ', gzip' : ''})',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    _BodyPreview(bytes: request.bodyBytes),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders a captured request body. We show two views:
///   * the first [_kBodyPreviewByteLimit] bytes as a hex/ASCII dump; and
///   * a UTF-8 decode attempt, falling back to a notice when bytes are not
///     valid UTF-8 (e.g. gzipped payloads).
class _BodyPreview extends StatelessWidget {
  const _BodyPreview({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (bytes.isEmpty) {
      return Text('(empty)', style: theme.textTheme.bodySmall);
    }
    final bool truncated = bytes.length > _kBodyPreviewByteLimit;
    final Uint8List preview = truncated
        ? Uint8List.sublistView(bytes, 0, _kBodyPreviewByteLimit)
        : bytes;

    final String hex = _formatHexDump(preview);
    final String? text = _tryDecodeUtf8(preview);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (text != null) ...<Widget>[
          Text('Text', style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text('Hex', style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SelectableText(
            hex,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
        if (truncated)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Preview truncated to $_kBodyPreviewByteLimit bytes of '
              '${bytes.length}.',
              style: theme.textTheme.labelSmall,
            ),
          ),
      ],
    );
  }

  static String? _tryDecodeUtf8(Uint8List bytes) {
    try {
      return const Utf8Decoder(allowMalformed: false).convert(bytes);
    } on FormatException {
      return null;
    }
  }

  /// Produces a classic 16-column hex dump:
  /// `00000000  7b 22 6b 22 3a 31 7d  {"k":1}`
  static String _formatHexDump(Uint8List bytes) {
    const int rowWidth = 16;
    final StringBuffer out = StringBuffer();
    for (int offset = 0; offset < bytes.length; offset += rowWidth) {
      final int end =
          (offset + rowWidth < bytes.length) ? offset + rowWidth : bytes.length;
      final StringBuffer hex = StringBuffer();
      final StringBuffer ascii = StringBuffer();
      for (int i = offset; i < offset + rowWidth; i++) {
        if (i < end) {
          final int b = bytes[i];
          hex.write(b.toRadixString(16).padLeft(2, '0'));
          hex.write(' ');
          ascii.write((b >= 0x20 && b < 0x7f) ? String.fromCharCode(b) : '.');
        } else {
          hex.write('   ');
          ascii.write(' ');
        }
        if (i == offset + 7) hex.write(' ');
      }
      out.write(offset.toRadixString(16).padLeft(8, '0'));
      out.write('  ');
      out.write(hex.toString());
      out.write(' ');
      out.write(ascii.toString());
      out.writeln();
    }
    return out.toString();
  }
}
