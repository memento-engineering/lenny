import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/contract.dart';

class _HandlerExtension extends LeonardExtension {
  _HandlerExtension({required this.namespace, required this.handlers});

  @override
  final String namespace;

  final List<ErrorHandler> handlers;

  @override
  List<LeonardTool> get tools => const [];

  @override
  Future<void> initialize(ExtensionContext ctx) async {
    for (final h in handlers) {
      ctx.registerErrorHandler(h);
    }
  }


  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scheduler = SchedulerBinding.instance;

  test('extension method is auto-namespaced', () {
    expect(
      ExtensionContext.buildExtensionMethodName('router', 'ping'),
      'ext.exploration.router.ping',
    );
  });

  test('error handlers run in order; first true short-circuits', () async {
    final calls = <String>[];
    final r = ExtensionRegistry(scheduler: scheduler);
    r.register(_HandlerExtension(
      namespace: 'a',
      handlers: <ErrorHandler>[
        (FlutterErrorDetails _) {
          calls.add('a');
          return false;
        },
      ],
    ));
    r.register(_HandlerExtension(
      namespace: 'b',
      handlers: <ErrorHandler>[
        (FlutterErrorDetails _) {
          calls.add('b');
          return true;
        },
      ],
    ));
    r.register(_HandlerExtension(
      namespace: 'c',
      handlers: <ErrorHandler>[
        (FlutterErrorDetails _) {
          calls.add('c');
          return true;
        },
      ],
    ));
    await r.initializeAll();
    final claimed = r.dispatchError(
      FlutterErrorDetails(exception: StateError('x')),
    );
    expect(claimed, isTrue);
    expect(calls, <String>['a', 'b']);
  });

  testWidgets('frame callback forwards to scheduler', (tester) async {
    var fired = false;
    final ctx = ExtensionContext(
      namespace: 'a',
      scheduler: SchedulerBinding.instance,
    );
    ctx.registerFrameCallback((_) {
      fired = true;
    });
    // testWidgets installs LiveTestWidgetsFlutterBinding-equivalent that
    // does not pump frames automatically; trigger one and wait briefly
    // (the plan's scheduleFrame + 16ms recipe).
    SchedulerBinding.instance.scheduleFrame();
    await tester.pump(const Duration(milliseconds: 16));
    expect(fired, isTrue);
  });
}
