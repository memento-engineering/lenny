/// Test-support alias for `serializePerceptionFragment`, kept so existing
/// extension tests import it from one stable path. The implementation now lives
/// in `genesis_perception`; this re-exports it.
library;

export 'package:genesis_perception/genesis_perception.dart'
    show serializePerceptionFragment;
