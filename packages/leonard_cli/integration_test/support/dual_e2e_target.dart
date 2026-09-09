import 'dart:io';

import 'package:path/path.dart' as p;

/// The resolved paths used by a dual e2e suite.
///
/// `app` is the native app bundle and `flutterProject` is the Flutter project
/// root used as the launch working directory.
typedef DualE2eTarget = ({String app, String flutterProject});

/// Resolves independently overridable target paths for the dual e2e suites.
///
/// The in-repo Flutter sample app is the default project. When only the project
/// is overridden, its iOS simulator build becomes the default app. Non-empty
/// overrides are preserved exactly as supplied.
DualE2eTarget resolveDualE2eTarget({
  required String packageRoot,
  Map<String, String>? environment,
}) {
  final Map<String, String> resolvedEnvironment =
      environment ?? Platform.environment;
  final String defaultFlutterProject = p.normalize(
    p.join(packageRoot, '..', 'leonard_flutter', 'example', 'sample_app'),
  );
  final String flutterProject =
      resolvedEnvironment['LEONARD_NATIVE_FLUTTER_PROJECT']?.isNotEmpty == true
      ? resolvedEnvironment['LEONARD_NATIVE_FLUTTER_PROJECT']!
      : defaultFlutterProject;
  final String app =
      resolvedEnvironment['LEONARD_NATIVE_APP']?.isNotEmpty == true
      ? resolvedEnvironment['LEONARD_NATIVE_APP']!
      : p.join(flutterProject, 'build', 'ios', 'iphonesimulator', 'Runner.app');

  return (app: app, flutterProject: flutterProject);
}
