import 'dart:convert';
import 'dart:io';

import 'package:leonard_contract/leonard_contract.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Calls both binding extensions on the first VM isolate and returns raw JSON.
Future<Map<String, Object?>> probePanelVmService(VmService vm) async {
  final VM state = await vm.getVM();
  final List<IsolateRef> isolates = state.isolates ?? const <IsolateRef>[];
  if (isolates.isEmpty) {
    throw StateError('Panel DWDS connection has no isolates.');
  }
  final String? isolateId = isolates.first.id;
  if (isolateId == null) {
    throw StateError('First panel DWDS isolate has no id.');
  }
  final List<String?> isolateIds = <String?>[
    for (final IsolateRef isolate in isolates) isolate.id,
  ];
  final Response handshake = await vm.callServiceExtension(
    '$kLeonardExtensionPrefix.core.handshake',
    isolateId: isolateId,
  );
  final Response observation = await vm.callServiceExtension(
    '$kLeonardExtensionPrefix.core.get_stable_observation',
    isolateId: isolateId,
    args: const <String, dynamic>{'policy': 'action-relative'},
  );
  return <String, Object?>{
    'isolate_ids': isolateIds,
    'isolate_id': isolateId,
    'handshake': handshake.json,
    'observation': observation.json,
  };
}

Future<void> main(List<String> args) async {
  if (args.length != 1 ||
      !(args.single.startsWith('ws://') || args.single.startsWith('wss://'))) {
    stderr.writeln(
      'usage: dart run panel_selfdrive_probe.dart <panel-dwds-ws-uri>',
    );
    exitCode = 64;
    return;
  }

  VmService? vm;
  try {
    vm = await vmServiceConnectUri(args.single);
    stdout.writeln(jsonEncode(await probePanelVmService(vm)));
  } catch (error) {
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'error_type': error.runtimeType.toString(),
        'error': error.toString(),
      }),
    );
    exitCode = 1;
  } finally {
    if (vm != null) await vm.dispose();
  }
}
