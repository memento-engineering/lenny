/// Errors raised by the leonard_agent harness library.
library;

/// Thrown when the target app's [LeonardBinding] is not initialized,
/// i.e. the `ext.leonard.core.handshake` service extension is absent.
///
/// The message reproduces the host setup snippet from PRD §7.6 so users
/// see the exact code change required in their app's `main()`.
class BindingNotInitializedError extends StateError {
  BindingNotInitializedError() : super(_msg);

  static const String _msg = '''
LeonardBinding is not initialized in the target app.
Add to your app's main():

  void main() {
    if (kDebugMode) {
      LeonardBinding.ensureInitialized(extensions: [/* your extensions */]);
    } else {
      WidgetsFlutterBinding.ensureInitialized();
    }
    runApp(MyApp());
  }
''';
}

/// Thrown when `get_stable_observation` does not return an observation
/// envelope this harness can decode.
///
/// Deliberately NOT a [StateError]: `DefaultLoopHost._callTransport`
/// translates `StateError` into `VmServiceConnectionLost` because
/// `package:vm_service` throws a bare `StateError` after `dispose()`. A
/// malformed envelope is a CONTRACT failure with a healthy transport, and
/// must keep its own identity all the way to the trajectory footer.
class ObservationEnvelopeError extends Error {
  /// Creates an error for [isolateId] and the response [topLevelKeys].
  factory ObservationEnvelopeError({
    required String isolateId,
    required Iterable<String> topLevelKeys,
  }) {
    final List<String> keys = topLevelKeys.toList()..sort();
    return ObservationEnvelopeError._(
      isolateId,
      List<String>.unmodifiable(keys),
    );
  }

  ObservationEnvelopeError._(this.isolateId, this.topLevelKeys);

  /// Isolate pinned by `VmServiceClient` for the failing extension call.
  final String isolateId;

  /// Sorted keys present on the raw VM-service response.
  final List<String> topLevelKeys;

  /// Footer-safe rendering of [topLevelKeys], e.g. `[error, type]`.
  String get keySummary => '[${topLevelKeys.join(', ')}]';

  @override
  String toString() =>
      'ObservationEnvelopeError: malformed Observation envelope from '
      'isolate "$isolateId"; top-level keys: $keySummary. Expected value '
      'to contain either a semantics list or an extensions map.';
}
