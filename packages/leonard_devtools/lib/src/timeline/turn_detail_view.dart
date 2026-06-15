import 'dart:async';
import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Decodes base64 strings to bytes. Indirected so widget tests can
/// observe how often (and when) decoding happens — the AC requires
/// screenshot bytes only be decoded after the user opens the
/// expansion tile.
typedef ScreenshotDecoder = Uint8List Function(String base64Payload);

/// Default decoder backed by `dart:convert`.
Uint8List defaultScreenshotDecoder(String b64) => base64Decode(b64);

/// Detail view pushed when a [TurnRow] is tapped. Renders the proposed
/// + executed action, validation, model reasoning, route stack,
/// semantics summary (with expandable JSON), each plugin fragment
/// (also lazy JSON), and the screenshot if attached (lazy decode).
class TurnDetailView extends StatelessWidget {
  const TurnDetailView({
    super.key,
    required this.record,
    this.screenshotDecoder = defaultScreenshotDecoder,
  });

  final TurnRecord record;

  /// Indirected so tests can count decodes.
  final ScreenshotDecoder screenshotDecoder;

  @override
  Widget build(BuildContext context) {
    final core = record.observation['core'];
    final plugins = record.observation['extensions'];
    final routeStack = (core is Map ? core['route_stack'] : null);
    final routeLabel = routeStack is List
        ? routeStack.map((s) => s.toString()).join(' -> ')
        : '(no route stack)';
    final semanticsNodes = (core is Map ? core['nodes'] : null);
    final nodeCount = semanticsNodes is List ? semanticsNodes.length : 0;

    final reasoning = _readReasoning(record);
    final screenshotB64 = _readScreenshot(record);

    return Scaffold(
      appBar: AppBar(title: Text('Turn #${record.index}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Executed action',
            child: SelectableText(_formatAction(record.executedAction)),
          ),
          _Section(
            title: 'Proposed action',
            child: SelectableText(_formatAction(record.proposedAction)),
          ),
          _Section(
            title: 'Validation',
            child: SelectableText(_formatValidation(record.validation)),
          ),
          _Section(
            title: 'Reasoning',
            child: SelectableText(reasoning ?? '(none)'),
          ),
          _Section(
            title: 'Route stack',
            child: SelectableText(routeLabel),
          ),
          _Section(
            title: 'Semantics nodes ($nodeCount)',
            child: ExpansionTile(
              title: const Text('Show JSON'),
              children: [
                LazyJson(
                  builder: () => semanticsNodes ?? const <dynamic>[],
                ),
              ],
            ),
          ),
          if (plugins is Map)
            for (final entry in plugins.entries)
              _Section(
                title: 'Plugin: ${entry.key}',
                child: ExpansionTile(
                  title: const Text('Show JSON'),
                  children: [
                    LazyJson(builder: () => entry.value),
                  ],
                ),
              ),
          if (screenshotB64 != null)
            _Section(
              title: 'Screenshot',
              child: ExpansionTile(
                title: const Text('Show image'),
                children: [
                  LazyImage(
                    base64Payload: screenshotB64,
                    decoder: screenshotDecoder,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _formatAction(Map<String, dynamic> action) {
    final tool = action['tool'] as String? ?? '<unknown>';
    final args = action['args'];
    final argsLabel = args == null ? '{}' : jsonEncode(args);
    return '$tool($argsLabel)';
  }

  static String _formatValidation(Map<String, dynamic> validation) {
    final result = validation['result'];
    final retries = validation['retries'];
    if (result == 'ok') {
      return 'OK${retries == null ? '' : ' (retries $retries)'}';
    }
    return 'Rejected: $result${retries == null ? '' : ' (retries $retries)'}';
  }

  static String? _readReasoning(TurnRecord r) {
    final fromMeta = r.modelMetadata['reasoning'];
    if (fromMeta is String && fromMeta.isNotEmpty) return fromMeta;
    final fromTop = (r.observation['reasoning']);
    if (fromTop is String && fromTop.isNotEmpty) return fromTop;
    return null;
  }

  static String? _readScreenshot(TurnRecord r) {
    final core = r.observation['core'];
    if (core is Map) {
      final s = core['screenshot_base64'];
      if (s is String && s.isNotEmpty) return s;
    }
    final top = r.observation['screenshot_base64'];
    if (top is String && top.isNotEmpty) return top;
    return null;
  }
}

/// Defers the JSON encoding of a map/list until built (which only
/// happens after the parent ExpansionTile is opened).
@visibleForTesting
class LazyJson extends StatelessWidget {
  const LazyJson({super.key, required this.builder});

  final Object? Function() builder;

  @override
  Widget build(BuildContext context) {
    final value = builder();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SelectableText(
        const JsonEncoder.withIndent('  ').convert(value),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}

/// Defers base64 decode until built. Wrapped in [FutureBuilder] so the
/// decode itself never blocks the widget tree synchronously.
@visibleForTesting
class LazyImage extends StatefulWidget {
  const LazyImage({
    super.key,
    required this.base64Payload,
    required this.decoder,
  });

  final String base64Payload;
  final ScreenshotDecoder decoder;

  @override
  State<LazyImage> createState() => _LazyImageState();
}

class _LazyImageState extends State<LazyImage> {
  late final Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = Future.microtask(() => widget.decoder(widget.base64Payload));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Image.memory(snapshot.data!, gaplessPlayback: true);
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}
