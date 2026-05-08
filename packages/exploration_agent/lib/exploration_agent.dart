/// Web-compatible harness library. MUST NOT import dart:io.
library;

export 'src/errors.dart' show BindingNotInitializedError;
export 'src/observation/diff_models.dart'
    show
        ChangedValue,
        CoreDiff,
        NodeChange,
        ObservationDiff,
        PluginDiff,
        PluginDiffAdded,
        PluginDiffOpaque,
        PluginDiffRemoved,
        PluginDiffStructured,
        RouteChange;
export 'src/observation/observation_differ.dart' show ObservationDiffer;
export 'src/observation/models.dart'
    show
        CoreFragment,
        Observation,
        PluginBusy,
        PluginFragment,
        RuntimeError,
        SemanticsNode,
        StabilityMetadata;
export 'src/provider/provider.dart';
export 'src/session.dart' show ExplorationSession;
export 'src/session/observation_puller.dart' show StabilityPolicy;
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
export 'src/trajectory/reader.dart' show TrajectoryReader;
export 'src/trajectory/records.dart'
    show
        PluginDisabledEvent,
        PluginManifestRecord,
        SessionFooter,
        SessionHeader,
        SessionOutcome,
        TrajectoryRecord,
        TurnRecord,
        UnknownTrajectoryRecord;
export 'src/trajectory/sink.dart' show TrajectorySink;
export 'src/trajectory/writer.dart' show TrajectoryWriter;
export 'src/vm_service_client.dart' show VmServiceClient;
