/// The Leonard *contract* extension for a native mobile app.
///
/// A stateful, self-watching extension — the same shape as `TmuxExtension` and
/// the Flutter reference extensions: [initialize] connects the [NativeBackend]
/// and subscribes to its [NativeBackend.watch] poll loop, keeping a live
/// [NativeSnapshot] current, so [buildPerception] reads it **synchronously**
/// (ADR-0006). There is no async work at observation time; the async I/O lives
/// behind the backend seam. Tools (`tap`, `enter_text`, `press`, `swipe`)
/// resolve a selector and act through the backend, then refresh the snapshot so
/// the next observation reflects the action promptly.
library;

import 'dart:async';

import 'package:genesis_perception/genesis_perception.dart';
import 'package:leonard_contract/leonard_contract.dart';

import 'native_backend.dart';
import 'native_perception.dart';
import 'native_snapshot.dart';

/// Wires a [NativeBackend] into Leonard as the `native` extension.
class NativeExtension extends LeonardExtension with PerceptionExtension {
  /// Observes and drives [backend].
  NativeExtension(this.backend);

  /// The backend this extension observes and drives.
  final NativeBackend backend;

  StreamSubscription<NativeSnapshot>? _sub;
  NativeSnapshot? _live;
  bool _refreshing = false;
  bool _disposed = false;

  @override
  String get namespace => 'native';

  @override
  List<LeonardTool> get tools => <LeonardTool>[
    _TapTool(this),
    _EnterTextTool(this),
    _PressTool(this),
    _SwipeTool(this),
  ];

  @override
  Future<void> initialize(ExtensionContext ctx) async {
    await backend.connect();
    _sub = backend.watch().listen(
      (NativeSnapshot snap) {
        _live = snap;
      },
      // A transient poll error must not kill the host isolate; keep last-good.
      onError: (Object _) {},
      cancelOnError: false,
    );
    _live = await backend.snapshot();
  }

  /// Pre-build seam: a no-op. The watcher keeps [_live] current out-of-band,
  /// so observation is a pure synchronous read.
  @override
  void prepareForObservation() {}

  @override
  bool isPerceptionIdle() => _live == null;

  @override
  Seed buildPerception() => NativePerception(_live!);

  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _sub?.cancel();
    _sub = null;
    await backend.close();
  }

  /// Force-refresh the cache now (after a mutating tool), so the next
  /// observation reflects the tap/text without waiting for a poll tick. No-op
  /// after dispose; swallows transient failures to keep the last-good snapshot.
  Future<void> refreshNow() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    try {
      _live = await backend.snapshot();
    } on Object {
      // Keep the last good snapshot on a transient gather failure.
    } finally {
      _refreshing = false;
    }
  }

  /// Shared selector resolution: builds a [NativeSelector] from the tool args
  /// and delegates to [NativeBackend.resolve], which walks the chain
  /// a11y-id -> label -> xpath -> rect-center.
  Future<NativeTarget?> resolveTarget(Map<String, Object?> args) {
    final NativeSelector sel = NativeSelector(
      a11yId: args['id'] as String?,
      label: args['label'] as String?,
      xpath: args['xpath'] as String?,
      rect: (args['rect'] as List?)?.cast<int>(),
    );
    return backend.resolve(sel, _live);
  }
}

/// Shared selector-arg schema properties for the three selector-based tools.
const Map<String, Object?> _selectorProps = <String, Object?>{
  'id': <String, Object?>{
    'type': 'string',
    'description': 'a11y identifier (tier 1)',
  },
  'label': <String, Object?>{
    'type': 'string',
    'description': 'visible label (tier 2)',
  },
  'xpath': <String, Object?>{
    'type': 'string',
    'description':
        "XPath, e.g. //XCUIElementTypeTextField[@name='Email address'] "
        '(tier 3)',
  },
  'rect': <String, Object?>{
    'type': 'array',
    'items': <String, Object?>{'type': 'integer'},
    'description': '[l,t,r,b]; taps the center (tier 4, last resort)',
  },
};

class _TapTool extends LeonardTool {
  _TapTool(this._ext);

  final NativeExtension _ext;

  @override
  String get name => 'tap';

  @override
  String get description =>
      'Tap a native element. Resolve it by a11y id, label, XPath, or rect '
      '(tried in that order; the winning tier is reported as `via`).';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': _selectorProps,
    'additionalProperties': false,
  });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final NativeTarget? t = await _ext.resolveTarget(args);
    if (t == null) {
      return const ToolResult(ok: false, error: 'no element matched selector');
    }
    try {
      await _ext.backend.tap(t);
    } on NativeException catch (e) {
      return ToolResult(ok: false, error: e.message);
    }
    await _ext.refreshNow();
    return ToolResult(ok: true, value: <String, Object?>{'via': t.via});
  }
}

class _EnterTextTool extends LeonardTool {
  _EnterTextTool(this._ext);

  final NativeExtension _ext;

  @override
  String get name => 'enter_text';

  @override
  String get description =>
      'Clear and type text into a native field, then dismiss the keyboard. '
      'Returns the element-type-derived `masked` flag and the `readback` '
      'value (a secure field reads back masked bullets, never plaintext).';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      ..._selectorProps,
      'text': <String, Object?>{'type': 'string'},
    },
    'required': <String>['text'],
    'additionalProperties': false,
  });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final Object? text = args['text'];
    if (text is! String) {
      return const ToolResult(ok: false, error: 'text is required');
    }
    final NativeTarget? t = await _ext.resolveTarget(args);
    if (t == null) {
      return const ToolResult(ok: false, error: 'no element matched selector');
    }
    final ({String readback, bool masked}) r;
    try {
      r = await _ext.backend.enterText(t, text);
    } on NativeException catch (e) {
      return ToolResult(ok: false, error: e.message);
    }
    await _ext.refreshNow();
    return ToolResult(
      ok: true,
      value: <String, Object?>{
        'via': t.via,
        'readback': r.readback,
        'masked': r.masked,
      },
    );
  }
}

class _PressTool extends LeonardTool {
  _PressTool(this._ext);

  final NativeExtension _ext;

  @override
  String get name => 'press';

  @override
  String get description =>
      'Issue a logical key press. iOS: enter/return/done/consent_accept/'
      'alert_dismiss (consent_accept accepts the iOS sign-in consent alert; '
      'alert_dismiss dismisses an iOS system alert, e.g. the Save Password '
      'prompt). Android: back. An unrecognized key is a structured error.';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'key': <String, Object?>{'type': 'string'},
    },
    'required': <String>['key'],
    'additionalProperties': false,
  });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final Object? key = args['key'];
    if (key is! String || key.isEmpty) {
      return const ToolResult(ok: false, error: 'key is required');
    }
    try {
      await _ext.backend.press(key);
    } on NativeException catch (e) {
      return ToolResult(ok: false, error: e.message);
    }
    await _ext.refreshNow();
    return ToolResult(ok: true, value: <String, Object?>{'key': key});
  }
}

class _SwipeTool extends LeonardTool {
  _SwipeTool(this._ext);

  final NativeExtension _ext;

  @override
  String get name => 'swipe';

  @override
  String get description =>
      'Swipe from one point to another (each [x,y] ints). Optional '
      'duration_ms (default 300).';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'from': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'integer'},
        'description': '[x,y] start point',
      },
      'to': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'integer'},
        'description': '[x,y] end point',
      },
      'duration_ms': <String, Object?>{'type': 'integer'},
    },
    'required': <String>['from', 'to'],
    'additionalProperties': false,
  });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    final List<int>? from = (args['from'] as List?)?.cast<int>();
    final List<int>? to = (args['to'] as List?)?.cast<int>();
    if (from == null || from.length != 2 || to == null || to.length != 2) {
      return const ToolResult(
        ok: false,
        error: 'from and to must each be a 2-int [x,y] array',
      );
    }
    final NativeSwipe gesture = NativeSwipe(
      fromX: from[0],
      fromY: from[1],
      toX: to[0],
      toY: to[1],
      durationMs: args['duration_ms'] as int? ?? 300,
    );
    try {
      await _ext.backend.swipe(gesture);
    } on NativeException catch (e) {
      return ToolResult(ok: false, error: e.message);
    }
    await _ext.refreshNow();
    return ToolResult(ok: true, value: <String, Object?>{});
  }
}
