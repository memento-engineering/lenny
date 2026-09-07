/// I/O-only VM-service connection and session assembly.
///
/// This is the single library under `leonard_agent/lib` allowed to import the
/// VM-service socket transport. Keep web-safe consumers on
/// `package:leonard_agent/leonard_agent.dart`.
library;

import 'package:vm_service/vm_service.dart' show VmService;
import 'package:vm_service/vm_service_io.dart';

import 'multi_host/multi_host_session.dart';
import 'session.dart';
import 'vm_service_client.dart';

/// Opens an owned VM-service connection to [wsUri] and pins its first isolate.
Future<VmServiceClient> connectVmServiceClient(Uri wsUri) async {
  final VmService vm = await vmServiceConnectUri(wsUri.toString());
  return VmServiceClient.fromOwnedVmService(vm);
}

/// Opens an owned VM-service connection and wraps it in a [LeonardSession].
///
/// Call [LeonardSession.start] before observing or acting.
Future<LeonardSession> connectLeonardSession(Uri vmServiceUri) async {
  final VmServiceClient client = await connectVmServiceClient(vmServiceUri);
  return LeonardSession.fromVmServiceClient(client);
}

/// Opens one owned VM-service connection for each host, in attach order.
///
/// If a later attachment fails, every client opened earlier in the sequence is
/// disposed before the error is rethrown.
Future<MultiHostSession> connectMultiHostSession(
  List<HostAttachment> hosts,
) async {
  if (hosts.isEmpty) {
    throw ArgumentError.value(
      hosts,
      'hosts',
      'connectMultiHostSession requires at least one host',
    );
  }

  final List<({String label, VmServiceClient client})> clients =
      <({String label, VmServiceClient client})>[];
  try {
    for (final HostAttachment host in hosts) {
      final VmServiceClient client = await connectVmServiceClient(host.uri);
      clients.add((label: host.label, client: client));
    }
  } on Object {
    for (final ({String label, VmServiceClient client}) connection in clients) {
      await connection.client.dispose();
    }
    rethrow;
  }
  return MultiHostSession.fromVmServiceClients(clients);
}
