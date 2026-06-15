import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leonard_flutter/contract.dart';
import 'package:leonard_flutter/leonard_flutter.dart';

/// A plugin whose error handler we can drive from tests.
class _RecordingExtension extends LeonardExtension {
  _RecordingExtension(this.namespace, {required this.handler});

  @override
  final String namespace;
  final bool Function(FlutterErrorDetails) handler;

  @override
  List<LeonardTool> get tools => const <LeonardTool>[];

  @override
  Future<void> initialize(ExtensionContext ctx) async {
    ctx.registerErrorHandler(handler);
  }

  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  // First plugin: never claims, but records every call.
  final List<String> firstCalls = <String>[];
  final _RecordingExtension firstPlugin = _RecordingExtension(
    'alpha',
    handler: (FlutterErrorDetails d) {
      firstCalls.add(d.exceptionAsString());
      return false;
    },
  );

  // Second plugin: throws on every call.
  final _RecordingExtension throwerPlugin = _RecordingExtension(
    'beta',
    handler: (FlutterErrorDetails _) {
      throw StateError('handler boom');
    },
  );

  // Third plugin: claims errors whose message contains 'CLAIM'.
  final List<String> thirdCalls = <String>[];
  final _RecordingExtension claimerPlugin = _RecordingExtension(
    'gamma',
    handler: (FlutterErrorDetails d) {
      thirdCalls.add(d.exceptionAsString());
      return d.exceptionAsString().contains('CLAIM');
    },
  );

  late LeonardBinding binding;

  setUpAll(() async {
    binding = LeonardBinding.ensureInitialized(
      extensions: <LeonardExtension>[firstPlugin, throwerPlugin, claimerPlugin],
    )!;
    // Plugin initialization runs in a microtask; flush it so the error
    // handlers are registered before the first test fires errors.
    await Future<void>.delayed(Duration.zero);
  });

  test('error hooks are installed exactly once even after a second '
      'ensureInitialized call', () {
    expect(binding.debugErrorHooksInstalled(), isTrue);
    final FlutterExceptionHandler? wrappedFlutter = FlutterError.onError;
    // Idempotency: second call returns same instance and does not re-hook.
    final LeonardBinding? again = LeonardBinding.ensureInitialized(
      extensions: const [],
    );
    expect(identical(binding, again), isTrue);
    expect(
      identical(FlutterError.onError, wrappedFlutter),
      isTrue,
      reason: 'second ensureInitialized must not re-install hooks',
    );
  });

  test(
    'every error is recorded into the ring regardless of handler return',
    () {
      final int before = binding.debugHighestErrorSeq();
      binding.debugAppendError('first', StackTrace.current);
      binding.debugAppendError('second', StackTrace.current);
      expect(binding.debugHighestErrorSeq(), before + 2);
    },
  );

  test('FlutterError.onError wrapper records, dispatches, and forwards', () {
    firstCalls.clear();
    thirdCalls.clear();
    final int beforeSeq = binding.debugHighestErrorSeq();

    // Capture the prior handler's invocations by stashing the wrapper and
    // checking the framework default still receives the report. The
    // framework default would normally print to stderr; flutter_test
    // converts thrown errors via FlutterError.reportError into test
    // failures. We use FlutterError.onError directly with a synthesised
    // FlutterErrorDetails to avoid tripping the test runner's failure
    // surface.
    final FlutterErrorDetails details = FlutterErrorDetails(
      exception: StateError('uh oh'),
      stack: StackTrace.current,
      library: 'test',
    );
    FlutterError.onError!(details);

    expect(
      binding.debugHighestErrorSeq(),
      beforeSeq + 1,
      reason: 'ring buffer must record',
    );
    expect(firstCalls, hasLength(1), reason: 'first plugin handler must run');
    expect(
      thirdCalls,
      hasLength(1),
      reason:
          'thrower plugin handler exception must not block subsequent '
          'plugin handlers',
    );
  });

  test('first claimer short-circuits the chain, but ring still records', () {
    firstCalls.clear();
    thirdCalls.clear();
    final int beforeSeq = binding.debugHighestErrorSeq();

    final FlutterErrorDetails details = FlutterErrorDetails(
      exception: StateError('CLAIM this one'),
      stack: StackTrace.current,
      library: 'test',
    );
    FlutterError.onError!(details);

    expect(binding.debugHighestErrorSeq(), beforeSeq + 1);
    // first plugin (alpha) returns false → chain advances
    expect(firstCalls, hasLength(1));
    // beta throws → counts as not-claiming
    // gamma sees 'CLAIM' → returns true → chain stops at gamma
    expect(thirdCalls, hasLength(1));
  });

  test('PlatformDispatcher.onError wrapper records and forwards', () {
    final int beforeSeq = binding.debugHighestErrorSeq();
    final bool handled = PlatformDispatcher.instance.onError!(
      StateError('platform-level'),
      StackTrace.current,
    );
    expect(binding.debugHighestErrorSeq(), beforeSeq + 1);
    expect(
      handled,
      isTrue,
      reason:
          'when no prior platform onError exists the wrapper '
          'reports handled (matches framework default)',
    );
  });

  test('ring entry shape matches schema', () {
    final int beforeSeq = binding.debugHighestErrorSeq();
    binding.debugAppendError(
      'shape-check',
      StackTrace.fromString('#0 a\n#1 b\n#2 c\n#3 d\n#4 e\n#5 f\n#6 g'),
    );
    final List<ErrorEntry> entries = binding.debugErrorEntries();
    final ErrorEntry e = entries.last;
    expect(e.seq, beforeSeq + 1);
    expect(e.message, 'shape-check');
    expect(e.frames.length, 5, reason: 'frames are capped at the first 5');
    expect(e.frames.first, '#0 a');
    expect(e.wallClockOffsetMs, isA<int>());
    expect(e.wallClockOffsetMs, greaterThanOrEqualTo(0));
  });

  test('extensionRegistry getter exposes the wired registry', () {
    expect(binding.extensionRegistry, isNotNull);
    final Map<String, LeonardTool> merged = binding.extensionRegistry
        .mergedTools();
    // The host-installed CoreExtension contributes the 10 `core.*` tools
    // even when no user plugins are supplied. Recording plugins from
    // this test fixture expose none of their own.
    final List<String> coreKeys = const <String>[
      'core.tap',
      'core.long_press',
      'core.enter_text',
      'core.scroll',
      'core.scroll_until_visible',
      'core.gesture',
      'core.system_back',
      'core.wait',
      'core.inspect_widget',
      'core.done',
    ];
    expect(merged.keys.toSet(), coreKeys.toSet());
  });
}
