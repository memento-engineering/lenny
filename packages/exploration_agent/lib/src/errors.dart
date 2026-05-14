/// Errors raised by the exploration_agent harness library.
library;

/// Thrown when the target app's [ExplorationBinding] is not initialized,
/// i.e. the `ext.flutter.exploration.core.handshake` service extension is absent.
///
/// The message reproduces the host setup snippet from PRD §7.6 so users
/// see the exact code change required in their app's `main()`.
class BindingNotInitializedError extends StateError {
  BindingNotInitializedError() : super(_msg);

  static const String _msg = '''
ExplorationBinding is not initialized in the target app.
Add to your app's main():

  void main() {
    if (kDebugMode) {
      ExplorationBinding.ensureInitialized(plugins: [/* your plugins */]);
    } else {
      WidgetsFlutterBinding.ensureInitialized();
    }
    runApp(MyApp());
  }
''';
}
