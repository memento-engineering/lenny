import 'dart:convert';
import 'dart:io';

import 'package:genesis_perception/genesis_perception.dart';
import 'package:leonard_contract/leonard_contract.dart';
import 'package:leonard_host/leonard_host.dart';

Future<void> main() async {
  final ExplorationHost host = ExplorationHost(
    extensions: const <LeonardExtension>[ExampleExtension()],
  );
  final Map<String, Object?> observation =
      jsonDecode(await host.observationJson()) as Map<String, Object?>;
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(observation));
}

class ExampleExtension extends LeonardExtension with PerceptionExtension {
  const ExampleExtension();

  @override
  String get namespace => 'example';

  @override
  List<LeonardTool> get tools => const <LeonardTool>[];

  @override
  Future<void> initialize(ExtensionContext ctx) async {}

  @override
  Component buildPerception() => const ExamplePerception();

  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {}
}

class ExamplePerception extends StatelessPerception {
  const ExamplePerception({super.key});

  @override
  Component build(PerceptionContext context) => const Node(
    'example',
    children: <Component>[Field('message', 'hello from pure Dart')],
  );
}
