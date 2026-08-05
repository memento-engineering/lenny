import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/android_permission_dialog_proof.dart';

void main() {
  late AndroidPermissionDialogProof proof;
  late Map<String, Object?> receipt;

  Map<String, Object?> copyReceipt() =>
      jsonDecode(jsonEncode(receipt)) as Map<String, Object?>;

  setUp(() {
    proof = AndroidPermissionDialogProof(
      runProcess: (String executable, List<String> arguments) async =>
          ProcessResult(1, 0, '', ''),
    );
    receipt = <String, Object?>{
      'schemaVersion': 1,
      'rawSourceSha256': 'a' * 64,
      'capturedAtUtc': '2026-08-04T22:00:00.000Z',
      'serial': serial,
      'androidVersion': '13',
      'manufacturer': 'samsung',
      'model': 'SM-M225FV',
      'package': packageName,
      'permission': permission,
      'appiumVersion': '3.5.2',
      'uiautomator2Version': '6.3.0',
      'appiumEvidence': <String, Object?>{'exitCode': 0},
      'uiautomator2Evidence': <String, Object?>{'exitCode': 0},
      'appiumRequests': <Object?>[
        <String, Object?>{
          'method': 'GET',
          'path': '/session/s1/source',
          'status': 200,
          'value': '<hierarchy/>',
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

  test('accepts attributed source and exactly three safe actions', () {
    expect(() => proof.validateReceipt(receipt, 'a' * 64), returnsNormally);
  });

  for (final String field in <String>[
    'serial',
    'androidVersion',
    'manufacturer',
    'model',
    'appiumVersion',
    'uiautomator2Version',
  ]) {
    test('rejects wrong $field', () {
      final Map<String, Object?> changed = copyReceipt()..[field] = '';
      expect(() => proof.validateReceipt(changed, 'a' * 64), throwsStateError);
    });
  }

  test('rejects changed fixture hash', () {
    expect(() => proof.validateReceipt(receipt, 'b' * 64), throwsStateError);
  });

  test('rejects missing source request', () {
    final Map<String, Object?> changed = copyReceipt()
      ..['appiumRequests'] = <Object?>[];
    expect(() => proof.validateReceipt(changed, 'a' * 64), throwsStateError);
  });

  test('rejects non-zero command evidence', () {
    final Map<String, Object?> changed = copyReceipt();
    (changed['appiumEvidence']! as Map)['exitCode'] = 1;
    expect(() => proof.validateReceipt(changed, 'a' * 64), throwsStateError);
  });

  for (final (String name, int action, String field, Object? value)
      in <(String, int, String, Object?)>[
        ('absent pre-action dialog', 0, 'dialogBefore', false),
        ('Back request', 0, 'backPosted', true),
        ('allow denied', 1, 'grantedAfter', false),
        ('deny granted', 2, 'grantedAfter', true),
      ]) {
    test('rejects $name', () {
      final Map<String, Object?> changed = copyReceipt();
      ((changed['actions']! as List)[action] as Map)[field] = value;
      expect(() => proof.validateReceipt(changed, 'a' * 64), throwsStateError);
    });
  }
}
