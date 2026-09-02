import 'dart:convert';
import 'dart:io';

/// Environment names whose VALUES are credentials.
///
/// `SWIFT_INFER_ENDPOINT` is deliberately absent: the panel scenario TYPES
/// the endpoint into the panel's Endpoint field, so once the observation
/// tree is visible the URL legitimately appears in node labels, in
/// `core.enter_text` arguments, and in the trajectory. It is configuration,
/// not a credential.
const List<String> kSecretNames = <String>[
  'SWIFT_INFER_AGENT_TOKEN',
  'ANTHROPIC_API_KEY',
  'OPENAI_API_KEY',
];

/// Thrown when a receipt assertion fails. `main` renders it to stderr and
/// sets `exitCode = 1` on a normal return, so the diagnostics block on
/// stdout is always flushed first.
class ReceiptInvalid implements Exception {
  ReceiptInvalid(this.message);

  /// The failed assertion.
  final String message;

  @override
  String toString() => 'panel self-drive receipt invalid: $message';
}

/// Replaces every credential value in [text] with `<REDACTED:NAME>`.
String redactSecrets(String text, Map<String, String> secrets) {
  String out = text;
  for (final MapEntry<String, String> secret in secrets.entries) {
    out = out.replaceAll(secret.value, '<REDACTED:${secret.key}>');
  }
  return out;
}

/// Redacts leaked credential values in every capture IN PLACE, updating
/// [captureText]. Evidence is never deleted. Returns the sorted names that
/// leaked; empty means the scan is clean.
Future<List<String>> redactCapturesInPlace(
  Map<File, String> captureText,
  Map<String, String> secrets,
) async {
  final Set<String> leaked = <String>{};
  for (final File capture in captureText.keys.toList()) {
    final String before = captureText[capture]!;
    final String after = redactSecrets(before, secrets);
    if (after == before) continue;
    for (final MapEntry<String, String> secret in secrets.entries) {
      if (before.contains(secret.value)) leaked.add(secret.key);
    }
    await capture.writeAsString(after);
    captureText[capture] = after;
  }
  return leaked.toList()..sort();
}

/// Decodes JSONL, skipping a truncated final line rather than losing the
/// whole trajectory to one partial write.
List<Map<String, dynamic>> decodeRecords(String text) {
  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
  for (final String line in const LineSplitter().convert(text)) {
    if (line.trim().isEmpty) continue;
    try {
      final Object? decoded = jsonDecode(line);
      if (decoded is Map) out.add(decoded.cast<String, dynamic>());
    } on FormatException {
      continue;
    }
  }
  return out;
}

/// Trajectory-derived evidence a negative receipt quotes verbatim.
List<String> receiptDiagnostics(List<Map<String, dynamic>> records) {
  final List<Map<String, dynamic>> turns = records
      .where((Map<String, dynamic> record) => record['type'] == 'turn')
      .toList(growable: false);
  final int nonEmpty = turns
      .where((Map<String, dynamic> turn) => _nodes(turn).isNotEmpty)
      .length;
  final Map<dynamic, dynamic> lastAction = turns.isEmpty
      ? const <dynamic, dynamic>{}
      : turns.last['proposed_action'] as Map<dynamic, dynamic>? ??
            const <dynamic, dynamic>{};
  final Map<String, dynamic> footer = records.lastWhere(
    (Map<String, dynamic> record) => record['type'] == 'footer',
    orElse: () => const <String, dynamic>{},
  );
  final Set<String> labels = <String>{
    for (final Map<String, dynamic> turn in turns) ..._observationText(turn),
  };
  return <String>[
    'TURN_COUNT=${turns.length}',
    'NON_EMPTY_NODE_TURN_COUNT=$nonEmpty',
    'LAST_PROPOSED_ACTION=${lastAction['tool'] ?? 'none'}',
    'FOOTER_OUTCOME=${footer['outcome'] ?? 'absent'}',
    'FOOTER_HARNESS_ERROR=${footer['harness_error'] ?? 'none'}',
    'FOOTER_TERMINATION_DETAIL=${footer['termination_detail'] ?? 'none'}',
    'STOP_OBSERVED=${labels.contains('Stop')}',
    'SELECT_MODEL_ERROR_OBSERVED=${labels.contains('Select a model')}',
  ];
}

/// `panel_probe.json`-derived evidence: the observation envelope's own keys
/// plus the truncation-marker byte counts when present.
List<String> probeDiagnostics(String? probeJson) {
  Map<dynamic, dynamic> value = const <dynamic, dynamic>{};
  if (probeJson != null && probeJson.trim().isNotEmpty) {
    try {
      final Object? decoded = jsonDecode(probeJson);
      final Object? observation = decoded is Map
          ? decoded['observation']
          : null;
      final Object? raw = observation is Map ? observation['value'] : null;
      if (raw is Map) value = raw;
    } on FormatException {
      value = const <dynamic, dynamic>{};
    }
  }
  final List<String> keys = <String>[for (final Object? k in value.keys) '$k']
    ..sort();
  return <String>[
    'PANEL_PROBE_OBSERVATION_KEYS=${keys.isEmpty ? 'absent' : keys.join(',')}',
    'PANEL_PROBE_ORIGINAL_BYTES=${value['originalBytes'] ?? 'absent'}',
    'PANEL_PROBE_BUDGET_BYTES=${value['budgetBytes'] ?? 'absent'}',
  ];
}

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln(
      'usage: dart run tool/verify_panel_selfdrive_receipt.dart '
      '<trajectory.jsonl> <driver.log> <harness.log> [capture ...]',
    );
    exitCode = 64;
    return;
  }
  final List<File> captures = <File>[
    for (final String path in args) File(path),
  ];
  final Map<String, String> secrets = <String, String>{
    for (final String name in kSecretNames)
      if (Platform.environment[name]?.isNotEmpty == true)
        name: Platform.environment[name]!,
  };
  final Map<File, String> captureText = <File, String>{};
  for (final File capture in captures) {
    if (!await capture.exists()) continue;
    captureText[capture] = await capture.readAsString();
  }
  final List<String> leaked = await redactCapturesInPlace(captureText, secrets);
  for (final String name in leaked) {
    stderr.writeln(
      'secret scan redacted in captured output: $name value found',
    );
  }

  final List<Map<String, dynamic>> records = decodeRecords(
    captureText[captures.first] ?? '',
  );
  String? probeText;
  for (final MapEntry<File, String> entry in captureText.entries) {
    if (entry.key.path.endsWith('panel_probe.json')) {
      probeText = entry.value;
    }
  }
  stdout.writeln(
    'CAPTURED_OUTPUT_SECRET_SCAN='
    '${leaked.isEmpty ? 'clean' : 'leak-redacted'}',
  );
  for (final String line in receiptDiagnostics(records)) {
    stdout.writeln(line);
  }
  for (final String line in probeDiagnostics(probeText)) {
    stdout.writeln(line);
  }

  if (leaked.isNotEmpty) {
    stderr.writeln(
      'panel self-drive receipt invalid: credential value redacted in '
      'captured output; captured files retained',
    );
    exitCode = 2;
    return;
  }

  try {
    _assertReceipt(captures, captureText, records);
  } on ReceiptInvalid catch (e) {
    stderr.writeln('$e');
    exitCode = 1;
  }
}

void _assertReceipt(
  List<File> captures,
  Map<File, String> captureText,
  List<Map<String, dynamic>> records,
) {
  for (final File capture in captures) {
    if (!captureText.containsKey(capture)) {
      _fail('capture is missing: ${capture.path}');
    }
  }

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
  if (!turnText.any((List<String> values) => values.contains('Stop'))) {
    _fail('no running-session Stop button observed after Start');
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
  stdout.writeln('OBSERVED_TURN_INDEX=${observedRow.group(1)}');
  stdout.writeln('OBSERVED_TURN_TOOL=${observedRow.group(2)}');
  stdout.writeln('PROMPT_FORM=enabled');
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

Never _fail(String message) => throw ReceiptInvalid(message);
