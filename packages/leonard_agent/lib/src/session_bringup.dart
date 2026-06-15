/// Shared session bring-up helper used by `leonard_cli` and
/// `AgentDogfoodHarness`.
///
/// Encapsulates the post-start bring-up sequence that was duplicated across
/// both call sites: handshake walk → `ExtensionManifestRecord` list
/// → `SessionHeader` construction → `DefaultLoopHost.fromSession`.
///
/// **Contract:** the caller must call `session.start(goal, config)` (and
/// optionally `.timeout(...)`) BEFORE calling [bringUpSession].
/// [bringUpSession] reads `session.handshake` and assumes it is populated.
///
/// The caller retains responsibility for:
///   - constructing, connecting, and starting the [LeonardSession],
///   - choosing provider, VmService origin, and trace writer,
///   - writing the returned [header] to its own writer, and
///   - handing the returned [host] to `session.run` / `LoopDriver`.
library;

import 'loop_driver/default_loop_host.dart';
import 'provider/types.dart';
import 'session.dart';
import 'session/observation_puller.dart';
import 'trajectory/records.dart';
import 'types.dart';

/// Result returned by [bringUpSession].
///
/// A named record (Dart 3 inline record) so callers can destructure:
/// ```dart
/// final (:header, :host) = await bringUpSession(...);
/// ```
typedef BringUpResult = ({SessionHeader header, DefaultLoopHost host});

/// Build the plugin manifest, assemble a [SessionHeader], compose a
/// [DefaultLoopHost], and return both.
///
/// **Pre-condition:** [session] must have already been started via
/// `session.start(goal, config)` before this function is called.
///
/// Parameters:
/// * [session] — already-started; `session.handshake` must be populated.
/// * [goal] — inserted into header and host.
/// * [policy] — stability policy for observation polling.
/// * [modelIdentifier] — stamped into the header.
/// * [buildIdentifier] — stamped into the header.
/// * [harnessVersion] — stamped into the header.
/// * [coreTools] — base tools always included in `host.mergedTools()`.
/// * [extensionTools] — per-namespace tool descriptors (caller builds from
///   `session.handshake.plugins` after `session.start` returns).
/// * [agentsMd] — pre-loaded AGENTS.md text forwarded to the host.
/// * [agentsMdHash] — hash stamped into the header (defaults to `''`).
/// * [extraConfig] — additional key/value pairs merged into
///   `header.config` (may be null).
Future<BringUpResult> bringUpSession({
  required LeonardSession session,
  required String goal,
  required StabilityPolicy policy,
  required String modelIdentifier,
  required String buildIdentifier,
  required String harnessVersion,
  required List<ToolDescriptor> coreTools,
  required Map<String, List<ToolDescriptor>> extensionTools,
  required String agentsMd,
  String agentsMdHash = '',
  Map<String, dynamic>? extraConfig,
}) async {
  // session.start was called by the caller before bringUpSession.
  // Build the plugin manifest from the completed handshake.
  final List<ExtensionManifestRecord> manifest = <ExtensionManifestRecord>[
    for (final ExtensionManifestEntry p in session.handshake.plugins)
      ExtensionManifestRecord(
        namespace: p.namespace,
        packageVersion: 'unknown',
        contractVersion: session.handshake.contractVersion,
      ),
  ];

  final Map<String, dynamic> config0 = <String, dynamic>{
    if (extraConfig != null) ...extraConfig,
  };

  final SessionHeader header = SessionHeader(
    goal: goal,
    agentsMdHash: agentsMdHash,
    buildIdentifier: buildIdentifier,
    modelIdentifier: modelIdentifier,
    harnessVersion: harnessVersion,
    plugins: manifest,
    config: config0,
  );

  final DefaultLoopHost host = DefaultLoopHost.fromSession(
    session: session,
    coreTools: coreTools,
    extensionTools: extensionTools,
    goal: goal,
    agentsMd: agentsMd,
    policy: policy,
  );

  return (header: header, host: host);
}
