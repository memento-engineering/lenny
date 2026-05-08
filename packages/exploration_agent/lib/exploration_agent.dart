/// Web-compatible harness library. MUST NOT import dart:io.
library;

export 'src/errors.dart' show BindingNotInitializedError;
export 'src/provider/provider.dart';
export 'src/session.dart' show ExplorationSession;
export 'src/types.dart'
    show
        ExplorationConfig,
        HandshakeResult,
        PluginAutoDisabled,
        PluginManifestEntry,
        SessionEnded,
        SessionProgressEvent,
        SessionStarted,
        TurnBegan;
export 'src/trajectory/records.dart'
    show
        PluginDisabledEvent,
        PluginManifestRecord,
        SessionFooter,
        SessionHeader,
        SessionOutcome,
        TurnRecord;
export 'src/trajectory/sink.dart' show TrajectorySink;
export 'src/trajectory/writer.dart' show TrajectoryWriter;
export 'src/vm_service_client.dart' show VmServiceClient;
