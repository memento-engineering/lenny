/// Pure-Dart VM-service host for Leonard.
///
/// [ExplorationHost] exposes a set of `LeonardExtension`s over the same
/// `ext.exploration.*` VM-service surface the Flutter binding hosts — minus
/// the Flutter-only core fragment (semantics/routes/screenshot) — so a
/// non-Flutter Dart program can be perceived and acted on live by
/// `leonard_cli` / `leonard_drive`.
library;

export 'src/exploration_host.dart' show ExplorationHost;
