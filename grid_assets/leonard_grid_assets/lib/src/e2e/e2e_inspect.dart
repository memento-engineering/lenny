/// Typed Leonard trajectory inspection.
library;

import 'dart:convert';

import 'package:leonard_agent/leonard_agent.dart';

import 'e2e_run.dart';
import 'e2e_service.dart';
import 'e2e_session.dart';

/// Reads one trajectory and derives its verdict from typed records only.
Future<E2eVerdict> inspectE2eTrajectory(
  E2eRuntime runtime,
  E2eSessionRequest request,
  E2eRunReceipt receipt, {
  required String deviceId,
}) async {
  if (!await runtime.fileExists(receipt.trajectoryPath)) {
    return E2eVerdict.failed(
      code: E2eFailureCode.trajectoryMissing,
      model: request.model,
      device: deviceId,
      durationMilliseconds: 0,
      trajectoryPath: receipt.trajectoryPath,
      driverExitStatus: receipt.driverExitStatus,
    );
  }

  final List<TrajectoryRecord> records;
  try {
    records = TrajectoryReader.readAll(
      await runtime.readFile(receipt.trajectoryPath),
    );
  } on Object {
    return E2eVerdict.failed(
      code: E2eFailureCode.malformedTrajectory,
      model: request.model,
      device: deviceId,
      durationMilliseconds: 0,
      trajectoryPath: receipt.trajectoryPath,
      driverExitStatus: receipt.driverExitStatus,
    );
  }

  final List<SessionHeader> headers = <SessionHeader>[];
  final List<TurnRecord> turns = <TurnRecord>[];
  final List<SessionFooter> footers = <SessionFooter>[];
  final List<ExtensionDisabledEvent> disabled = <ExtensionDisabledEvent>[];
  bool unknownRecord = false;
  for (final TrajectoryRecord record in records) {
    switch (record) {
      case SessionHeader():
        headers.add(record);
      case TurnRecord():
        turns.add(record);
      case SessionFooter():
        footers.add(record);
      case ExtensionDisabledEvent():
        disabled.add(record);
      case UnknownTrajectoryRecord():
        unknownRecord = true;
      default:
        unknownRecord = true;
    }
  }

  final List<E2eFailureCode> failures = <E2eFailureCode>[];
  void fail(E2eFailureCode code) {
    if (!failures.contains(code)) failures.add(code);
  }

  final bool shaped =
      records.isNotEmpty &&
      headers.length == 1 &&
      turns.isNotEmpty &&
      footers.length == 1 &&
      records.first is SessionHeader &&
      records.last is SessionFooter &&
      !unknownRecord;
  if (!shaped) fail(E2eFailureCode.trajectoryShape);
  if (disabled.isNotEmpty) fail(E2eFailureCode.extensionDisabled);

  final SessionHeader? header = headers.length == 1 ? headers.single : null;
  final SessionFooter? footer = footers.length == 1 ? footers.single : null;
  if (header != null &&
      header.modelIdentifier != request.model.trajectoryIdentifier) {
    fail(E2eFailureCode.modelMismatch);
  }
  if (footer != null && footer.outcome != SessionOutcome.done) {
    fail(E2eFailureCode.outcomeNotDone);
  }

  final List<int> failedActionIndexes = <int>[];
  bool malformedAction = false;
  for (var index = 0; index < turns.length; index++) {
    final Object? result = turns[index].executedAction['result'];
    final Object? ok = result is Map ? result['ok'] : null;
    if (ok is! bool) {
      malformedAction = true;
    } else if (!ok) {
      failedActionIndexes.add(index);
    }
  }
  if (malformedAction) fail(E2eFailureCode.trajectoryShape);
  if (failedActionIndexes.length > 1 ||
      (failedActionIndexes.length == 1 &&
          failedActionIndexes.single == turns.length - 1)) {
    fail(E2eFailureCode.actionFailure);
  }

  if (turns.length >= 3) {
    final List<String> finalActions = turns
        .skip(turns.length - 3)
        .map(_actionIdentity)
        .toList(growable: false);
    if (finalActions.toSet().length == 1) {
      fail(E2eFailureCode.terminalLoop);
    }
  }

  final Map<String, Object?> evidence = _expectationEvidence(
    request.expectation,
    turns.isEmpty ? const <String, dynamic>{} : turns.last.observation,
  );
  if (evidence['matched'] == false) fail(E2eFailureCode.expectationUnmet);

  String? providerRequestId;
  for (final TurnRecord turn in turns) {
    if (turn.providerRequestId != null) {
      providerRequestId = turn.providerRequestId;
    }
  }
  return E2eVerdict(
    status: failures.isEmpty ? E2eVerdictStatus.pass : E2eVerdictStatus.fail,
    failureCodes: failures,
    model: request.model,
    device: deviceId,
    turns: turns.length,
    durationMilliseconds: footer?.totalDurationMs ?? 0,
    trajectoryPath: receipt.trajectoryPath,
    driverExitStatus: receipt.driverExitStatus,
    providerRequestId: providerRequestId,
    actionFailures: failedActionIndexes.length,
    expectationEvidence: evidence,
  );
}

String _actionIdentity(TurnRecord turn) => jsonEncode(<String, Object?>{
  'tool': turn.proposedAction['tool'],
  'args': turn.proposedAction['args'],
});

Map<String, Object?> _expectationEvidence(
  E2eObservationExpectation expectation,
  Map<String, dynamic> observation,
) {
  if (expectation.isEmpty) {
    return const <String, Object?>{'matched': true, 'requested': false};
  }
  final Object? rawCore = observation['core'];
  final Map<Object?, Object?> core = rawCore is Map
      ? rawCore
      : const <Object?, Object?>{};
  final Object? rawRoutes = core['routeStack'] ?? observation['routes'];
  final List<String> routes = rawRoutes is List
      ? rawRoutes.whereType<String>().toList(growable: false)
      : const <String>[];
  final String? expectedRoute = expectation.route;
  final bool routeMatched =
      expectedRoute == null ||
      routes.any((String route) => _sameRoute(route, expectedRoute));

  final List<Map<Object?, Object?>> nodes = <Map<Object?, Object?>>[];
  final Object? rawNodes = core['nodes'] ?? observation['semantics'];
  if (rawNodes is Map) {
    for (final Object? node in rawNodes.values) {
      if (node is Map) nodes.add(node);
    }
  } else if (rawNodes is List) {
    for (final Object? node in rawNodes) {
      if (node is Map) nodes.add(node);
    }
  }
  final String? expectedLabel = expectation.semanticsLabel;
  final String? expectedState = expectation.semanticsState;
  final List<Map<Object?, Object?>> labelled = expectedLabel == null
      ? const <Map<Object?, Object?>>[]
      : nodes
            .where(
              (Map<Object?, Object?> node) => node['label'] == expectedLabel,
            )
            .toList(growable: false);
  final bool semanticsMatched =
      expectedLabel == null ||
      labelled.any((Map<Object?, Object?> node) {
        final Object? state = node['state'];
        return state is List && state.contains(expectedState);
      });
  return <String, Object?>{
    'matched': routeMatched && semanticsMatched,
    if (expectedRoute != null) 'expected_route': expectedRoute,
    if (expectedRoute != null) 'observed_routes': routes,
    if (expectedLabel != null) 'expected_label': expectedLabel,
    if (expectedState != null) 'expected_state': expectedState,
    if (expectedLabel != null)
      'observed_states': <Object?>[
        for (final Map<Object?, Object?> node in labelled) node['state'],
      ],
  };
}

bool _sameRoute(String observed, String expected) {
  String normalize(String value) =>
      value.trim().replaceAll(RegExp(r'^/+|/+$'), '').toLowerCase();
  return normalize(observed) == normalize(expected);
}
