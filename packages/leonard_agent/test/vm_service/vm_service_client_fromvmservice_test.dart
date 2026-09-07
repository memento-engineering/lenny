/// Regression test for the web-safe construction path: building a
/// [VmServiceClient] / [LeonardSession] from an already-connected
/// [VmService] must not require `package:vm_service/vm_service_io.dart`
/// (which pulls in `dart:io` and crashes on web with
/// `Unsupported operation: Platform._version`).
library;

import 'dart:io';

import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

final RegExp _vmServiceIoImport = RegExp(
  r'''^\s*import\s+['"]package:vm_service/vm_service_io\.dart['"]''',
  multiLine: true,
);

Directory _packageRoot() {
  final List<Directory> candidates = <Directory>[
    Directory.current,
    Directory.fromUri(Directory.current.uri.resolve('packages/leonard_agent/')),
  ];
  for (final Directory candidate in candidates) {
    if (File('${candidate.path}/lib/leonard_agent.dart').existsSync()) {
      return candidate;
    }
  }
  throw StateError(
    'could not locate leonard_agent from ${Directory.current.path}',
  );
}

/// Hand-rolled fake — overrides only [callServiceExtension].
class _FakeVmService extends VmService {
  _FakeVmService() : super(const Stream<dynamic>.empty(), (_) {});

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    final r = Response();
    r.json = <String, dynamic>{
      'contractVersion': '1.0.0',
      'extensions': <Map<String, dynamic>>[],
    };
    return r;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test(
    'VmServiceClient.fromVmService handshakes without vm_service_io',
    () async {
      final client = VmServiceClient.fromVmService(_FakeVmService(), 'iso-1');
      final result = await client.handshake();
      expect(result.extensions, isEmpty);
      expect(result.contractVersion, equals('1.0.0'));
    },
  );

  test('LeonardSession.fromVmService starts without vm_service_io', () async {
    final session = LeonardSession.fromVmService(_FakeVmService(), 'iso-1');
    await session.start('goal', const LeonardConfig());
    expect(session.handshake.extensions, isEmpty);
    await session.end();
  });

  test('web-safe barrel does not expose the I/O entrypoint', () async {
    final Directory packageRoot = _packageRoot();
    final File barrel = File('${packageRoot.path}/lib/leonard_agent.dart');
    final String source = await barrel.readAsString();

    expect(source, isNot(contains('leonard_agent_io.dart')));
    expect(source, isNot(contains('src/vm_service_client_io.dart')));
  });

  test('VM-service I/O import is confined to the exact seam', () async {
    final Directory packageRoot = _packageRoot();
    final Directory lib = Directory('${packageRoot.path}/lib');
    final File seam = File('${lib.path}/src/vm_service_client_io.dart');
    final String dogfoodPrefix =
        '${Directory('${lib.path}/src/dogfood').absolute.path}'
        '${Platform.pathSeparator}';

    expect(
      seam.existsSync(),
      isTrue,
      reason: 'expected the I/O seam at ${seam.path}',
    );

    final List<String> offenders = <String>[];
    await for (final FileSystemEntity entity in lib.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final String absolutePath = entity.absolute.path;
      if (absolutePath == seam.absolute.path ||
          absolutePath.startsWith(dogfoodPrefix)) {
        continue;
      }
      if (_vmServiceIoImport.hasMatch(await entity.readAsString())) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders..sort(),
      isEmpty,
      reason: 'web-safe libraries must not import the VM-service I/O seam',
    );
  });
}
