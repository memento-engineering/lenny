/// The deny-all handler is the ONLY thing standing between a phase-1 run and
/// an agent with a shell. These tests pin that behaviour.
library;

import 'package:acp_dart/acp_dart.dart';
import 'package:leonard_acp/leonard_acp.dart';
import 'package:test/test.dart';

RequestPermissionRequest _request(List<PermissionOption> options) =>
    RequestPermissionRequest(
      sessionId: 's1',
      options: options,
      toolCall: ToolCallUpdate(toolCallId: 'tc1', title: 'Run bash'),
    );

PermissionOption _option(String id, PermissionOptionKind kind) =>
    PermissionOption(optionId: id, name: id, kind: kind);

void main() {
  late DenyAllAcpClient client;
  late List<String> denied;

  setUp(() {
    denied = <String>[];
    client = DenyAllAcpClient(
      onAgentMessage: (_) {},
      onAgentThought: (_) {},
      onDenied: denied.add,
    );
  });

  test('prefers reject_always over every other option', () async {
    final RequestPermissionResponse r = await client.requestPermission(
      _request(<PermissionOption>[
        _option('allow', PermissionOptionKind.allowAlways),
        _option('once', PermissionOptionKind.rejectOnce),
        _option('always', PermissionOptionKind.rejectAlways),
      ]),
    );
    expect(r.outcome, isA<SelectedOutcome>());
    expect((r.outcome as SelectedOutcome).optionId, 'always');
  });

  test('falls back to reject_once when reject_always is absent', () async {
    final RequestPermissionResponse r = await client.requestPermission(
      _request(<PermissionOption>[
        _option('allow', PermissionOptionKind.allowOnce),
        _option('once', PermissionOptionKind.rejectOnce),
      ]),
    );
    expect((r.outcome as SelectedOutcome).optionId, 'once');
  });

  test('NEVER selects an allow option, even as the only choice', () async {
    final RequestPermissionResponse r = await client.requestPermission(
      _request(<PermissionOption>[
        _option('allow', PermissionOptionKind.allowOnce),
      ]),
    );
    expect(
      r.outcome,
      isA<CancelledOutcome>(),
      reason: 'cancelling the turn is correct; allowing it is not',
    );
  });

  test('cancels when the agent offers no options at all', () async {
    final RequestPermissionResponse r = await client.requestPermission(
      _request(const <PermissionOption>[]),
    );
    expect(r.outcome, isA<CancelledOutcome>());
  });

  test('reports the tool title so attempts are visible', () async {
    await client.requestPermission(
      _request(<PermissionOption>[
        _option('once', PermissionOptionKind.rejectOnce),
      ]),
    );
    expect(denied, <String>['Run bash']);
  });

  test('falls back to the tool call id when the title is absent', () async {
    await client.requestPermission(
      RequestPermissionRequest(
        sessionId: 's1',
        options: <PermissionOption>[
          _option('once', PermissionOptionKind.rejectOnce),
        ],
        toolCall: ToolCallUpdate(toolCallId: 'tc-42'),
      ),
    );
    expect(denied, <String>['tc-42']);
  });
}
