import 'dart:convert';
import 'dart:io';

const List<String> _secretNames = <String>[
  'SWIFT_INFER_AGENT_TOKEN',
  'ANTHROPIC_API_KEY',
  'OPENAI_API_KEY',
];

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln(
      'usage: dart run tool/verify_panel_selfdrive_receipt.dart '
      '<trajectory.jsonl> <driver.log> <harness.log>',
    );
    exitCode = 64;
    return;
  }
  final List<File> captures = <File>[
    for (final String path in args) File(path),
  ];
  final Map<String, String> secrets = <String, String>{
    for (final String name in _secretNames)
      if (Platform.environment[name]?.isNotEmpty == true)
        name: Platform.environment[name]!,
  };
  final Map<File, String> captureText = <File, String>{};
  for (final File capture in captures) {
    if (!await capture.exists()) continue;
    final String text = await capture.readAsString();
    captureText[capture] = text;
    for (final MapEntry<String, String> secret in secrets.entries) {
      if (text.contains(secret.value)) {
        stderr.writeln(
          'secret scan failed in ${capture.path}: ${secret.key} value found',
        );
        exitCode = 2;
        return;
      }
    }
  }
  for (final File capture in captures) {
    if (!captureText.containsKey(capture)) {
      _fail('capture is missing: ${capture.path}');
    }
  }

  final List<Map<String, dynamic>> records = <Map<String, dynamic>>[
    for (final String line in const LineSplitter().convert(
      captureText[captures.first]!,
    ))
      if (line.trim().isNotEmpty)
        (jsonDecode(line) as Map).cast<String, dynamic>(),
  ];
  final List<Map<String, dynamic>> turns = records
      .where((Map<String, dynamic> record) => record['type'] == 'turn')
      .toList(growable: false);

  bool enteredMarker(String name) => turns.any((Map<String, dynamic> turn) {
    final Map<dynamic, dynamic> action =
        turn['proposed_action'] as Map<dynamic, dynamic>? ??
        const <dynamic, dynamic>{};
    final Map<dynamic, dynamic> actionArgs =
        action['args'] as Map<dynamic, dynamic>? ?? const <dynamic, dynamic>{};
    return action['tool'] == 'core.enter_text' &&
        actionArgs['text'] == '\${$name}';
  });
  for (final String name in <String>[
    'SWIFT_INFER_ENDPOINT',
    'SWIFT_INFER_AGENT_TOKEN',
    'PANEL_SELFDRIVE_MODEL_ID',
  ]) {
    if (!enteredMarker(name)) _fail('trajectory never entered \${$name}');
  }

  final List<List<String>> turnText = <List<String>>[
    for (final Map<String, dynamic> turn in turns) _observationText(turn),
  ];
  if (!turnText
      .expand((List<String> value) => value)
      .any(
        (String value) =>
            RegExp(r'^OK \([1-9][0-9]* models\)$').hasMatch(value),
      )) {
    _fail('no successful Test connection observation');
  }

  final RegExp rowPattern = RegExp(r'^#([0-9]+) ([A-Za-z0-9_.-]+)\(');
  RegExpMatch? observedRow;
  for (final String value in turnText.expand((List<String> value) => value)) {
    observedRow ??= rowPattern.firstMatch(value);
  }
  if (observedRow == null) _fail('no rendered TurnRecord row observed');
  if (!turnText.any(
    (List<String> values) =>
        values.contains('Proposed action') &&
        values.any(
          (String value) =>
              RegExp(r'^[A-Za-z0-9_.-]+\(').hasMatch(value) &&
              !value.startsWith('<unknown>'),
        ),
  )) {
    _fail('no non-empty Proposed action detail observed');
  }

  final Map<String, dynamic>? doneTurn = turns
      .cast<Map<String, dynamic>?>()
      .lastWhere((Map<String, dynamic>? turn) {
        final Map<dynamic, dynamic> action =
            turn?['proposed_action'] as Map<dynamic, dynamic>? ??
            const <dynamic, dynamic>{};
        return action['tool'] == 'core.done';
      }, orElse: () => null);
  if (doneTurn == null || !_startEnabled(doneTurn)) {
    _fail(
      'final core.done observation did not contain an enabled Start button',
    );
  }

  stdout.writeln('TRAJECTORY_PATH=${captures.first.absolute.path}');
  stdout.writeln('OBSERVED_TURN_INDEX=${observedRow!.group(1)}');
  stdout.writeln('OBSERVED_TURN_TOOL=${observedRow.group(2)}');
  stdout.writeln('PROMPT_FORM=enabled');
  stdout.writeln('CAPTURED_OUTPUT_SECRET_SCAN=clean');
}

List<Map<String, dynamic>> _nodes(Map<String, dynamic> turn) {
  final Map<dynamic, dynamic> observation =
      turn['observation'] as Map<dynamic, dynamic>? ??
      const <dynamic, dynamic>{};
  final Map<dynamic, dynamic> core =
      observation['core'] as Map<dynamic, dynamic>? ??
      const <dynamic, dynamic>{};
  final Object? raw = core['nodes'];
  if (raw is Map) {
    return <Map<String, dynamic>>[
      for (final Object? value in raw.values)
        if (value is Map) value.cast<String, dynamic>(),
    ];
  }
  if (raw is List) {
    return <Map<String, dynamic>>[
      for (final Object? value in raw)
        if (value is Map) value.cast<String, dynamic>(),
    ];
  }
  return const <Map<String, dynamic>>[];
}

List<String> _observationText(Map<String, dynamic> turn) => <String>[
  for (final Map<String, dynamic> node in _nodes(turn))
    for (final String key in const <String>['label', 'value'])
      if (node[key] case final String value when value.isNotEmpty) value,
];

bool _startEnabled(Map<String, dynamic> turn) => _nodes(turn).any(
  (Map<String, dynamic> node) =>
      node['label'] == 'Start' &&
      (node['actions'] as List<dynamic>? ?? const <dynamic>[]).contains(
        'tap',
      ) &&
      !(node['state'] as List<dynamic>? ?? const <dynamic>[]).contains(
        'disabled',
      ),
);

Never _fail(String message) {
  stderr.writeln('panel self-drive receipt invalid: $message');
  exit(1);
}
