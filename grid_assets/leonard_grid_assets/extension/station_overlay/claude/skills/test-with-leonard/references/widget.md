# Test lenny extensions without a device

Use plain `test()` cases so `LeonardBinding` installs before any Flutter test binding, then import `package:leonard_flutter_test/leonard_flutter_test.dart` and install `BindingVmServiceFake` to drive the binding in process. A tree-consuming extension can use the offline `BuildOwner` plus `RootWidget.attach` root-provider seam demonstrated at `packages/leonard_flutter/example/diagnostic_fixture/test/diagnostic_fixture_test.dart:15-22` and `packages/leonard_flutter/example/diagnostic_fixture/test/diagnostic_fixture_test.dart:44-68`.

## Exercise an extension through lenny's wire contract

**Proves:** A file-local extension installed on the real binding is discoverable and its tool result crosses the lenny VM-service envelope without a device. The barrel exports both test helpers at `packages/leonard_flutter_test/lib/leonard_flutter_test.dart:1-5`; the fake's declaration and constructor are at `packages/leonard_flutter_test/lib/src/binding_vm_service_fake.dart:34-39`. This setup is copied from `packages/leonard_flutter_test/test/binding_integration_test.dart:120-149`, and `_SampleEchoExtension` is the extension under test at `packages/leonard_flutter_test/test/binding_integration_test.dart:42-65`.

**Command:** `cd packages/leonard_flutter_test && flutter test test/binding_integration_test.dart`

**Setup:**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:leonard_flutter/leonard_flutter.dart';
import 'package:leonard_flutter_test/leonard_flutter_test.dart';

late LeonardBinding binding;
late BindingVmServiceFake fake;

setUpAll(() async {
  binding = LeonardBinding.ensureInitialized(
    extensions: <LeonardExtension>[_SampleEchoExtension()],
  )!;
  await Future<void>.delayed(Duration.zero);
  fake = BindingVmServiceFake(binding);
});

tearDownAll(() async {
  await fake.dispose();
});
```

**Falsifier:** Replace the extension return at `packages/leonard_flutter_test/test/binding_integration_test.dart:38-39` with `ToolResult(ok: true, value: 'wrong')`.

**Failure signature:** The tool round-trip reports `Expected: 'hello'` and `Actual: 'wrong'`.

## Compare an extension's observation shape

**Proves:** The harvested observation preserves the stable envelope fields and the extension fragment already present in the golden. The helper contract is at `packages/leonard_flutter_test/lib/src/observation_equivalence.dart:5-37`; the working Riverpod caller builds both maps and invokes it at `packages/leonard_riverpod/test/unit/extension/riverpod_perception_equivalence_test.dart:154-180`.

**Command:** `cd packages/leonard_riverpod && flutter test test/unit/extension/riverpod_perception_equivalence_test.dart`

**Assertion:** `assertObservationEquivalent(golden, harvestedObs);`

**Falsifier:** Replace the extensions entry at `packages/leonard_riverpod/test/unit/extension/riverpod_perception_equivalence_test.dart:178` with `'extensions': <String, Object?>{},`.

**Failure signature:** The comparison reports `extension "riverpod" fragment must match between legacy and perception paths`.

## False negatives

### False negative 1 — a Flutter test binding wins initialization

Calling `TestWidgetsFlutterBinding.ensureInitialized()` or using `testWidgets` first activates `AutomatedTestWidgetsFlutterBinding`, so the level-1 setup cannot install `LeonardBinding`. The refusal is implemented at `packages/leonard_flutter/lib/src/binding/leonard_binding.dart:180-187`, with the named incompatibility at `packages/leonard_flutter/lib/src/binding/leonard_binding.dart:185`, and exercised at `packages/leonard_flutter/test/unit/binding/binding_conflict_test.dart:6-22`.

The console starts with `Bad state: LeonardBinding cannot be installed: another WidgetsBinding (AutomatedTestWidgetsFlutterBinding) is already active.` and continues with `LeonardBinding is incompatible with IntegrationTestWidgetsFlutterBinding and other custom bindings (PRD §6.5).` This is a harness conflict, not an extension failure.

### False negative 2 — a perception-only namespace escapes comparison

`assertObservationEquivalent` iterates `legacyExtensions.keys` only, so it never compares an extension namespace found only in the perception map (`packages/leonard_flutter_test/lib/src/observation_equivalence.dart:24-37`). The false-green console signature is `All tests passed!` even though the extra namespace survived. Pair this helper with an explicit key-set assertion when perception is allowed to introduce namespaces.

## Level boundary

Level 1 cannot observe real VM-service discovery or transport, isolate selection, engine-backed rendering, real input, platform channels, or device OS behavior. Escalate those claims to level 2 in `references/scripted-device.md`, which runs against a simulator or emulator as routed by `grid_assets/leonard_grid_assets/extension/station_overlay/claude/skills/test-with-leonard/SKILL.md:19`.
