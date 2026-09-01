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

/// Thrown when `get_stable_observation` does not return the binding envelope.
class ObservationEnvelopeError extends StateError {
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

  ObservationEnvelopeError._(this.isolateId, this.topLevelKeys)
    : super(
        'Malformed Observation envelope from isolate "$isolateId"; '
        'top-level keys: [${topLevelKeys.join(', ')}]. Expected value to '
        'contain either a semantics list or an extensions map.',
      );

  /// Isolate pinned by [VmServiceClient] for the failing extension call.
  final String isolateId;

  /// Sorted keys present on the raw VM-service response.
  final List<String> topLevelKeys;
}
