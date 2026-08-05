import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/android_permission_dialog_proof.dart';

void main() {
  late AndroidPermissionDialogProof proof;
  late Map<String, Object?> receipt;

  Map<String, Object?> copyReceipt() =>
      jsonDecode(jsonEncode(receipt)) as Map<String, Object?>;
  Map<String, Object?> command(List<String> argv, {String stdout = ''}) =>
      <String, Object?>{
        'argv': argv,
        'exitCode': 0,
        'stdout': stdout,
        'stderr': '',
      };
  Future<void> rejects(Map<String, Object?> changed) async {
    await expectLater(
      proof.validateReceipt(
        changed,
        '61578849fa1e5513034da0dabee5bf12ab701e08f9ee69d1164988a2b0b5064e',
      ),
      throwsStateError,
    );
  }

  setUp(() {
    proof = AndroidPermissionDialogProof(
      runProcess: (String executable, List<String> arguments) async =>
          ProcessResult(1, 0, '', ''),
    );
    receipt = <String, Object?>{
      'schemaVersion': 1,
      'rawSourceSha256':
          '61578849fa1e5513034da0dabee5bf12ab701e08f9ee69d1164988a2b0b5064e',
      'capturedAtUtc': '2026-08-04T22:00:00.000Z',
      'serial': serial,
      'androidVersion': '13',
      'manufacturer': 'samsung',
      'model': 'SM-M225FV',
      'package': packageName,
      'permission': permission,
      'trigger': trigger,
      'appiumVersion': '3.5.2',
      'uiautomator2Version': '8.2.2',
      'appiumEvidence': command(<String>[
        '/opt/homebrew/bin/appium',
        '--version',
      ], stdout: '3.5.2\n'),
      'uiautomator2Evidence': command(<String>[
        '/opt/homebrew/bin/appium',
        'driver',
        'list',
        '--installed',
        '--json',
      ], stdout: '{"uiautomator2":{"version":"8.2.2"}}'),
      'resetAndTriggerEvidence': <Object?>[
        for (final List<String> argv in expectedResetArgv) command(argv),
      ],
      'appiumRequests': <Object?>[
        <String, Object?>{
          'method': 'GET',
          'path': '/session/capture/source',
          'status': 200,
          'value': '<hierarchy/>',
        },
        <String, Object?>{
          'method': 'DELETE',
          'path': '/session/capture',
          'status': 200,
          'value': null,
        },
      ],
      'actions': <Object?>[
        <String, Object?>{
          'key': 'dismiss_overlay',
          'result': 'refused: permission_allow or permission_deny',
          'dialogBefore': true,
          'dialogAfter': true,
          'grantedAfter': false,
          'backPosted': false,
        },
        <String, Object?>{
          'key': 'permission_allow',
          'result': 'returned',
          'dialogBefore': true,
          'dialogAfter': false,
          'grantedAfter': true,
          'backPosted': false,
        },
        <String, Object?>{
          'key': 'permission_deny',
          'result': 'returned',
          'dialogBefore': true,
          'dialogAfter': false,
          'grantedAfter': false,
          'backPosted': false,
        },
      ],
    };
  });

  test(
    'accepts complete source, command, reset, and action evidence',
    () async {
      await proof.validateReceipt(
        receipt,
        '61578849fa1e5513034da0dabee5bf12ab701e08f9ee69d1164988a2b0b5064e',
      );
    },
  );

  for (final String field in <String>[
    'serial',
    'androidVersion',
    'manufacturer',
    'model',
    'appiumVersion',
    'uiautomator2Version',
  ]) {
    test('rejects wrong $field', () async {
      await rejects(copyReceipt()..[field] = 'wrong');
    });
  }

  test('rejects changed fixture hash', () async {
    final Map<String, Object?> changed = copyReceipt()
      ..['rawSourceSha256'] = 'b' * 64;
    await rejects(changed);
  });
  test('rejects wrong trigger', () async {
    await rejects(copyReceipt()..['trigger'] = <Object?>[]);
  });
  test('rejects incomplete reset evidence', () async {
    final Map<String, Object?> changed = copyReceipt();
    (changed['resetAndTriggerEvidence']! as List).removeLast();
    await rejects(changed);
  });
  test('rejects reordered reset evidence', () async {
    final Map<String, Object?> changed = copyReceipt();
    final List<Object?> resets =
        changed['resetAndTriggerEvidence']! as List<Object?>;
    final Object? first = resets[0];
    resets[0] = resets[1];
    resets[1] = first;
    await rejects(changed);
  });
  test('rejects changed source value', () async {
    final Map<String, Object?> changed = copyReceipt();
    ((changed['appiumRequests']! as List).first as Map)['value'] = '<changed/>';
    await rejects(changed);
  });
  test('rejects missing capture deletion', () async {
    final Map<String, Object?> changed = copyReceipt();
    (changed['appiumRequests']! as List).removeLast();
    await rejects(changed);
  });
  test('rejects wrong action order', () async {
    final Map<String, Object?> changed = copyReceipt();
    (changed['actions']! as List).insert(
      0,
      (changed['actions']! as List).removeAt(1),
    );
    await rejects(changed);
  });
  test('rejects non-zero command evidence', () async {
    final Map<String, Object?> changed = copyReceipt();
    (changed['appiumEvidence']! as Map)['exitCode'] = 1;
    await rejects(changed);
  });

  for (final (String name, int action, String field, Object? value)
      in <(String, int, String, Object?)>[
        ('absent pre-action dialog', 0, 'dialogBefore', false),
        ('Back request', 0, 'backPosted', true),
        ('allow denied', 1, 'grantedAfter', false),
        ('deny granted', 2, 'grantedAfter', true),
      ]) {
    test('rejects $name', () async {
      final Map<String, Object?> changed = copyReceipt();
      ((changed['actions']! as List)[action] as Map)[field] = value;
      await rejects(changed);
    });
  }
}
