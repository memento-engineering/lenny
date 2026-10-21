/// Where `leonard_drive up` finds the `leonard_native` host script when
/// `--native-host` is omitted.
library;

import 'package:path/path.dart' as p;

/// Host candidates relative to the working directory, for in-repo
/// development: a lenny checkout's `packages/leonard_native`, or its root.
const List<String> kNativeHostCwdCandidates = <String>[
  'bin/leonard_native_host.dart',
  'packages/leonard_native/bin/leonard_native_host.dart',
];

/// The resolved host script, or `null` alongside every path that was tried.
class NativeHostResolution {
  /// Creates a resolution result.
  const NativeHostResolution(
    this.path,
    this.tried, {
    this.inPackageConfig = false,
  });

  /// The host script to run, or `null` when no candidate exists.
  final String? path;

  /// Every candidate path checked, in order.
  final List<String> tried;

  /// Whether the running program's package config resolved
  /// `package:leonard_native` to a file. `false` when the program does not
  /// depend on `leonard_native`, or runs AOT-compiled with no package config.
  final bool inPackageConfig;
}

/// Resolves the native host script, package config first.
///
/// [nativeLibraryUri] is `package:leonard_native/leonard_native.dart` as the
/// running isolate's package config resolves it — the consumer's config, so
/// a hosted `leonard_native` in the pub cache is found from any directory.
/// `null` when the consumer does not depend on `leonard_native`. The host
/// sits at `<package root>/bin/leonard_native_host.dart`.
///
/// The working-directory candidates are a fallback for development inside a
/// lenny checkout; [describeNativeHostMiss] explains a miss everywhere else.
NativeHostResolution resolveNativeHost({
  required Uri? nativeLibraryUri,
  required bool Function(String path) exists,
}) {
  final List<String> tried = <String>[];
  final bool inPackageConfig =
      nativeLibraryUri != null && nativeLibraryUri.isScheme('file');
  if (inPackageConfig) {
    final String packageRoot = p.dirname(
      p.dirname(p.fromUri(nativeLibraryUri)),
    );
    final String host = p.join(packageRoot, 'bin', 'leonard_native_host.dart');
    tried.add(host);
    if (exists(host)) {
      return NativeHostResolution(host, tried, inPackageConfig: true);
    }
  }
  for (final String candidate in kNativeHostCwdCandidates) {
    tried.add(candidate);
    if (exists(candidate)) {
      return NativeHostResolution(
        candidate,
        tried,
        inPackageConfig: inPackageConfig,
      );
    }
  }
  return NativeHostResolution(null, tried, inPackageConfig: inPackageConfig);
}

/// The error `leonard_drive up` prints when [resolution] found no host and
/// no `--native-host` was passed.
///
/// A program whose package config lacks `leonard_native` is told so, and how
/// to fix it, instead of only seeing the working-directory candidates that
/// exist inside a lenny checkout and nowhere else (lenny#199).
String describeNativeHostMiss(NativeHostResolution resolution) {
  final String tried = resolution.tried.join(', ');
  const String override =
      'or pass --native-host <path to '
      'leonard_native/bin/leonard_native_host.dart>.';
  if (!resolution.inPackageConfig) {
    return 'error: cannot find the leonard_native host: leonard_native is '
        "missing from this program's package config (or the program runs "
        'AOT-compiled, without one), and the working directory is not a '
        'lenny checkout (tried: $tried). Fix: add leonard_native to your '
        "pubspec's dependencies (dart pub add leonard_native) and run "
        'dart pub get, $override';
  }
  return 'error: cannot find the leonard_native host: leonard_native '
      'resolves through the package config, but its '
      'bin/leonard_native_host.dart is missing (tried: $tried). Run '
      'dart pub get to restore it, $override';
}
