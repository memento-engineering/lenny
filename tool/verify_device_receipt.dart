/// Rejects vacuous or incomplete live-device test receipts.
library;

import 'dart:io';

List<String> verifyDeviceReceipt(Map<String, String> logs) {
  final List<String> errors = <String>[];
  final String all = logs.entries
      .map((MapEntry<String, String> entry) => '${entry.key}\n${entry.value}')
      .join('\n');
  if (RegExp(r'\bskipped\b', caseSensitive: false).hasMatch(all)) {
    errors.add('receipt contains a skipped marker');
  }
  for (final String line in all.split('\n')) {
    if (!line.startsWith('OBSTACLE ')) continue;
    if (!RegExp(r'^OBSTACLE lenny-[a-z0-9]+\s+\S').hasMatch(line)) {
      errors.add('OBSTACLE line must name its blocking bead: $line');
    }
  }

  void require(String marker, String reason) {
    if (!all.contains(marker)) errors.add(reason);
  }

  if (all.contains('android-permission-probe') ||
      all.contains('grant_dialog_source_diff')) {
    require(
      'HARDWARE_ASSERT lenny-m3sj grant_dialog_source_diff '
          'udid=RF8RB21P6LN',
      'm22 permission-source assertion is absent',
    );
  }
  if (all.contains('Android Auth0') || all.contains('dashboard_logged_in')) {
    for (final String marker in <String>[
      'HARDWARE_ASSERT lenny-m3sj dismiss_overlay_refused udid=RF8RB21P6LN',
      'HARDWARE_ASSERT lenny-bv7y resource_id udid=RF8RB21P6LN',
      'HARDWARE_ASSERT lenny-2d9z injected_capability udid=RF8RB21P6LN',
      'HARDWARE_ASSERT dashboard_logged_in udid=RF8RB21P6LN',
      'LOGGED_IN',
    ]) {
      require(marker, 'Android receipt is missing $marker');
    }
    require('+1', 'Android live test did not report execution (+1)');
  }
  if (all.contains('xcuitest_w3c_sim')) {
    require('+1', 'iOS simulator live test did not report execution (+1)');
  }
  if (all.contains('attach_bundle_id')) {
    require(
      'udid=00008110-001651523CE3801E',
      'iPad attach receipt has the wrong or absent device serial',
    );
    require(
      'appium_app=absent',
      'iPad receipt does not prove appium:app absent',
    );
    require('+1', 'iPad live test did not report execution (+1)');
  }
  if (!all.contains('HARDWARE_ASSERT') && !all.contains('OBSTACLE ')) {
    errors.add('receipt contains neither hardware assertions nor an obstacle');
  }
  return errors;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/verify_device_receipt.dart <log>...');
    exitCode = 64;
    return;
  }
  final Map<String, String> logs = <String, String>{};
  for (final String path in args) {
    final File file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('missing receipt log: $path');
      exitCode = 1;
      return;
    }
    logs[path] = await file.readAsString();
  }
  final List<String> errors = verifyDeviceReceipt(logs);
  if (errors.isNotEmpty) {
    for (final String error in errors) {
      stderr.writeln('receipt rejected: $error');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('DEVICE_RECEIPT_VERIFIED logs=${args.join(',')}');
}
