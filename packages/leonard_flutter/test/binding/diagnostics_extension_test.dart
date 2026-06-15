import 'dart:convert';
import 'dart:developer' as developer;

import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const String _diagnosticsExt =
    'ext.exploration.core.diagnostics_warnings';

/// All tests in this file run as plain `test()` (not `testWidgets`) so the
/// process never installs `AutomatedTestWidgetsFlutterBinding` before our
/// `LeonardBinding.ensureInitialized` call. Once a Flutter binding is
/// installed in a process it cannot be torn down (PRD §6.5), so all
/// assertions share a single binding via `setUpAll`.
void main() {
  late LeonardBinding binding;

  setUpAll(() {
    binding = LeonardBinding.ensureInitialized(plugins: const [])!;
  });

  tearDown(() {
    binding.debugSetDiagnosticsRootProviderForTesting(null);
  });

  test('extension is registered in debug/profile', () {
    expect(
      binding.debugHasRegisteredExtension(_diagnosticsExt),
      isTrue,
      reason: 'Diagnostics extension must be registered in debug/profile.',
    );
    // Re-registering the same name throws -> registration succeeded.
    expect(
      () => developer.registerExtension(
        _diagnosticsExt,
        (String m, Map<String, String> p) async =>
            developer.ServiceExtensionResponse.result('{}'),
      ),
      throwsArgumentError,
    );
  });

  test('release-mode gating: extension is debug/profile-only', () {
    // Mirror release_mode_test.dart: the gate lives behind kDebugMode ||
    // kProfileMode. We can't actually run release mode here, but we
    // assert the contract is queryable: the diagnostics name is properly
    // namespaced under core, and the registered-extension predicate is
    // well-defined.
    expect(_diagnosticsExt.startsWith('$kLeonardExtensionPrefix.core.'),
        isTrue);
    if (kReleaseMode) {
      expect(LeonardBinding.ensureInitialized(plugins: const []), isNull);
    } else {
      expect(binding.debugHasRegisteredExtension(_diagnosticsExt), isTrue);
    }
  });

  test('double call returns cached results without re-walking', () async {
    int providerCalls = 0;
    binding.debugSetDiagnosticsRootProviderForTesting(() {
      providerCalls += 1;
      return null; // Auditor returns []; we care about the call count.
    });

    final String first =
        await binding.invokeServiceExtension(_diagnosticsExt, const {});
    final Map<String, Object?> firstBody =
        jsonDecode(first) as Map<String, Object?>;
    expect(firstBody['ok'], isTrue);
    expect(firstBody['results'], isEmpty);
    expect(providerCalls, 1, reason: 'First call must walk exactly once.');

    final String second =
        await binding.invokeServiceExtension(_diagnosticsExt, const {});
    expect(second, equals(first),
        reason: 'Cached payload must come back byte-for-byte.');
    expect(providerCalls, 1,
        reason:
            'Second call must hit the cache; the root provider must not be '
            'invoked again.');
  });

  test('throwing root yields ok:false with empty results, no rethrow',
      () async {
    binding.debugSetDiagnosticsRootProviderForTesting(() {
      throw StateError('boom');
    });
    final String resp =
        await binding.invokeServiceExtension(_diagnosticsExt, const {});
    final Map<String, Object?> body =
        jsonDecode(resp) as Map<String, Object?>;
    expect(body['ok'], isFalse);
    expect((body['error']! as String), contains('boom'));
    expect(body['results'], isEmpty);
  });
}
