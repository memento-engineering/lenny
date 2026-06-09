/// Web-compatible harness library. MUST NOT import dart:io.
library;

export 'src/errors.dart' show BindingNotInitializedError;
export 'src/loop_driver/default_loop_host.dart' show DefaultLoopHost;
export 'src/loop_driver/loop_driver.dart' show LoopDriver;
export 'src/loop_driver/loop_host.dart' show LoopHost;
export 'src/loop_driver/plugin_failure_tracker.dart' show PluginFailureTracker;
export 'src/loop_driver/plugin_tools.dart'
    show buildPluginTools, unknownPluginNamespaces;
export 'src/loop_driver/validation_retry.dart'
    show
        InvalidActionExhausted,
        SchemaExhausted,
        ValidationLoopResult,
        decideAndValidate;
export 'src/loop_driver/types.dart'
    show
        HarnessError,
        HarnessErrorWire,
        SessionTermination,
        TurnFailure,
        TurnTimeoutError,
        VmServiceConnectionLost;
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
export 'src/prompt/conversation_builder.dart' show ConversationBuilder;
export 'src/prompt/default_agents_md.dart'
    show kDefaultAgentsMd, kDefaultAgentsMdHash, fnv1a32Hex;
export 'src/prompt/observation_renderer.dart'
    show JsonObservationRenderer, ObservationRenderer;
export 'src/provider/provider.dart';
export 'src/session.dart' show ExplorationSession;
export 'src/session_bringup.dart' show BringUpResult, bringUpSession;
export 'src/session/observation_puller.dart' show StabilityPolicy;
export 'src/session/turn_event.dart'
    show
        TurnActionDecided,
        TurnComplete,
        TurnEvent,
        TurnThinking,
        TurnUsage,
        TurnValidation;
export 'src/validation/action_validator.dart'
    show ActionValidator, ValidatorAction;
export 'src/validation/result.dart'
    show ValidationOk, ValidationReject, ValidationResult;
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
