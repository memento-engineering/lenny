/// Errors raised by the leonard_agent harness library.
library;

/// Thrown when the target app's [LeonardBinding] is not initialized,
/// i.e. the `ext.exploration.core.handshake` service extension is absent.
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
