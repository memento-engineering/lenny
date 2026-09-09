/// Thin grid capability adapters over the shared E2E service phases.
library;

import 'dart:convert';

import 'package:beads_dart/beads_dart.dart';
import 'package:genesis_tree/genesis_tree.dart';
import 'package:grid_assets/grid_assets.dart' show parentPath;
import 'package:grid_engine/grid_engine.dart';

import 'e2e_circuit.dart';
import 'e2e_launch.dart';
import 'e2e_preflight.dart';
import 'e2e_run.dart';
import 'e2e_service.dart';
import 'e2e_session.dart';

/// Runs the same deterministic preflight used by [E2eService.runSession].
class E2ePreflightCapability extends ServiceCapability {
  /// Creates the adapter.
  const E2ePreflightCapability(this.service);

  /// Shared service.
  final E2eService service;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final E2eOrder? order = _order(context);
    if (order == null) {
      return const Failed('leonard-e2e preflight: no complete E2E order');
    }
    try {
      final E2ePreflight cleared = await service.preflight(order.request);
      if (args.cancel.isCancelled) return const Failed('cancelled');
      return Ok(<String, String>{
        kE2eDeviceResultKey: cleared.device.id,
        if (cleared.modelId != null) kE2eModelIdResultKey: cleared.modelId!,
      });
    } on Object catch (error) {
      return Failed('leonard-e2e preflight: $error');
    }
  }
}

/// Holds the fresh Flutter process as the circuit's daemon lease.
class E2eLaunchCapability extends LeaseCapability<E2eLaunchHandle> {
  /// Creates the adapter.
  const E2eLaunchCapability(this.service);

  /// Shared service.
  final E2eService service;

  @override
  Future<LeaseResolution<E2eLaunchHandle>> acquire(
    TreeContext context,
    StepArgs args,
  ) async {
    final E2eOrder? order = _order(context);
    final SiblingView siblings = _siblings(context);
    if (order == null) {
      return const LeaseUnavailable<E2eLaunchHandle>(
        'leonard-e2e launch: no complete E2E order',
      );
    }
    final Map<String, String> preflight = siblings.resultOf(
      '${parentPath(args.nodePath)}/$kE2ePreflightStep',
    );
    final String deviceId = preflight[kE2eDeviceResultKey] ?? '';
    if (deviceId.isEmpty) {
      return const LeaseUnavailable<E2eLaunchHandle>(
        'leonard-e2e launch: preflight published no device',
      );
    }
    try {
      final E2eLaunchHandle handle = await service.launch(
        order.request,
        E2ePreflight(
          device: FlutterDevice(
            id: deviceId,
            name: deviceId,
            targetPlatform: 'ios',
            connectionInterface: 'attached',
            isSupported: true,
          ),
          modelId: preflight[kE2eModelIdResultKey],
        ),
      );
      if (args.cancel.isCancelled) {
        await service.teardown(handle);
        return const LeaseUnavailable<E2eLaunchHandle>('cancelled');
      }
      return LeaseBound<E2eLaunchHandle>(handle);
    } on Object catch (error) {
      return LeaseUnavailable<E2eLaunchHandle>('leonard-e2e launch: $error');
    }
  }

  @override
  Future<StepOutcome> dispatchOn(
    E2eLaunchHandle handle,
    TreeContext context,
    StepArgs args,
  ) async => Ok(<String, String>{
    kE2eDeviceResultKey: handle.deviceId,
    kE2eVmUriResultKey: handle.vmUri.toString(),
    kE2eRunDirResultKey: handle.runDir,
  });

  @override
  Future<void> release(E2eLaunchHandle handle) => service.teardown(handle);
}

/// Invokes Leonard and publishes its status as receipt data even when nonzero.
class E2eRunCapability extends ServiceCapability {
  /// Creates the adapter.
  const E2eRunCapability(this.service);

  /// Shared service.
  final E2eService service;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final E2eOrder? order = _order(context);
    final SiblingView siblings = _siblings(context);
    if (order == null) {
      return const Failed('leonard-e2e run: no complete E2E order');
    }
    final String circuitPath = parentPath(args.nodePath);
    final Map<String, String> launch = siblings.resultOf(
      '$circuitPath/$kE2eLaunchStep',
    );
    final Map<String, String> preflight = siblings.resultOf(
      '$circuitPath/$kE2ePreflightStep',
    );
    final String vmUri = launch[kE2eVmUriResultKey] ?? '';
    final String runDir = launch[kE2eRunDirResultKey] ?? '';
    if (vmUri.isEmpty || runDir.isEmpty) {
      return const Failed(
        'leonard-e2e run: launch published no URI or run dir',
      );
    }
    try {
      final E2eRunReceipt receipt = await service.run(
        order.request,
        vmUri: Uri.parse(vmUri),
        runDir: runDir,
        resolvedModelId: preflight[kE2eModelIdResultKey],
      );
      if (args.cancel.isCancelled) return const Failed('cancelled');
      return Ok(<String, String>{
        kE2eTrajectoryResultKey: receipt.trajectoryPath,
        kE2eDriverStatusResultKey: '${receipt.driverExitStatus}',
      });
    } on Object catch (error) {
      return Failed('leonard-e2e run: $error');
    }
  }
}

/// Performs the only circuit verdict conversion from typed inspection.
class E2eInspectCapability extends ServiceCapability {
  /// Creates the adapter.
  const E2eInspectCapability(this.service);

  /// Shared service.
  final E2eService service;

  @override
  Future<StepOutcome> run(TreeContext context, StepArgs args) async {
    final E2eOrder? order = _order(context);
    final SiblingView siblings = _siblings(context);
    if (order == null) {
      return const Failed('leonard-e2e inspect: no complete E2E order');
    }
    final String circuitPath = parentPath(args.nodePath);
    final Map<String, String> launch = siblings.resultOf(
      '$circuitPath/$kE2eLaunchStep',
    );
    final Map<String, String> run = siblings.resultOf(
      '$circuitPath/$kE2eRunStep',
    );
    final String deviceId = launch[kE2eDeviceResultKey] ?? '';
    final String trajectoryPath = run[kE2eTrajectoryResultKey] ?? '';
    final int? driverStatus = int.tryParse(
      run[kE2eDriverStatusResultKey] ?? '',
    );
    if (deviceId.isEmpty || trajectoryPath.isEmpty || driverStatus == null) {
      return const Failed(
        'leonard-e2e inspect: prior phases published an incomplete receipt',
      );
    }

    E2eVerdict verdict;
    try {
      verdict = await service.inspect(
        order.request,
        E2eRunReceipt(
          trajectoryPath: trajectoryPath,
          driverExitStatus: driverStatus,
          stdout: '',
          stderr: '',
        ),
        deviceId: deviceId,
      );
    } on Object catch (error) {
      verdict = E2eVerdict.failed(
        code: E2eFailureCode.unexpected,
        model: order.request.model,
        device: deviceId,
        durationMilliseconds: 0,
        trajectoryPath: trajectoryPath,
        driverExitStatus: driverStatus,
        evidence: <String, Object?>{'message': '$error'},
      );
    }
    if (args.cancel.isCancelled) return const Failed('cancelled');
    final String json = jsonEncode(verdict.toJson());
    return verdict.passed
        ? Ok(<String, String>{kE2eVerdictJsonResultKey: json})
        : Failed(json);
  }
}

E2eOrder? _order(TreeContext context) {
  final Bead? bead = context.getInheritedSeedOfExactType<Bead>();
  return bead == null ? null : E2eOrder.fromBead(bead);
}

SiblingView _siblings(TreeContext context) =>
    context.getInheritedSeedOfExactType<SiblingView>() ?? const SiblingView();
