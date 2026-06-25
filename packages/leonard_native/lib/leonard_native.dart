/// A pure-Dart Leonard *contract* extension for a native mobile app.
///
/// [NativeExtension] is a stateful, self-watching `LeonardExtension` (the same
/// shape as `TmuxExtension`): it subscribes to a [NativeBackend]'s a11y-tree
/// poll loop and keeps a live snapshot current, projecting it into a
/// genesis_perception tree that the host serializes into the `native`
/// observation fragment, and exposes `tap` / `enter_text` / `press` / `swipe`
/// tools. It observes the OS accessibility tree (via Appium/XCUITest) rather
/// than a Flutter widget tree — so it is pure Dart and uses no Flutter. Host it
/// over the VM service with `leonard_host`'s `ExplorationHost` to drive a
/// native app live.
library;

export 'src/appium_backend.dart' show AppiumBackend;
export 'src/fake_native_backend.dart' show FakeNativeBackend, FakeNativeCall;
export 'src/native_backend.dart'
    show
        NativeBackend,
        NativeSelector,
        NativeTarget,
        NativeSwipe,
        NativeException;
export 'src/native_extension.dart' show NativeExtension;
export 'src/native_perception.dart' show NativePerception;
export 'src/native_snapshot.dart' show NativeNode, NativeSnapshot;
