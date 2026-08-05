import 'package:test/test.dart';

import 'verify_device_receipt.dart';

void main() {
  test('rejects skipped Android live test', () {
    expect(
      verifyDeviceReceipt(<String, String>{
        'android-auth0.log': 'TEST SKIPPED\nAll tests passed!',
      }),
      isNotEmpty,
    );
  });

  test('rejects assertion omission', () {
    expect(
      verifyDeviceReceipt(<String, String>{
        'android-auth0.log': 'Android Auth0\n+1\nLOGGED_IN',
      }),
      isNotEmpty,
    );
  });

  test('rejects obstacle without a bead id', () {
    expect(
      verifyDeviceReceipt(<String, String>{
        'run.log': 'OBSTACLE missing-prerequisite no apk',
      }),
      isNotEmpty,
    );
  });

  test('accepts complete Android receipt', () {
    const String serial = 'udid=RF8RB21P6LN';
    expect(
      verifyDeviceReceipt(<String, String>{
        'android-auth0.log': <String>[
          'Android Auth0 +1 LOGGED_IN',
          'HARDWARE_ASSERT lenny-m3sj dismiss_overlay_refused $serial',
          'HARDWARE_ASSERT lenny-bv7y resource_id $serial',
          'HARDWARE_ASSERT lenny-2d9z injected_capability $serial',
          'HARDWARE_ASSERT dashboard_logged_in $serial',
        ].join('\n'),
      }),
      isEmpty,
    );
  });
}
