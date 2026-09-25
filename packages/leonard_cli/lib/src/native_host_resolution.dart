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
  const NativeHostResolution(this.path, this.tried);

  /// The host script to run, or `null` when no candidate exists.
  final String? path;

  /// Every candidate path checked, in order.
  final List<String> tried;
}

/// Resolves the native host script, package config first.
///
/// [nativeLibraryUri] is `package:leonard_native/leonard_native.dart` as the
/// running isolate's package config resolves it — the consumer's config, so
/// a hosted `leonard_native` in the pub cache is found from any directory.
/// `null` when the consumer does not depend on `leonard_native`. The host
/// sits at `<package root>/bin/leonard_native_host.dart`.
NativeHostResolution resolveNativeHost({
  required Uri? nativeLibraryUri,
  required bool Function(String path) exists,
}) {
  final List<String> tried = <String>[];
  if (nativeLibraryUri != null && nativeLibraryUri.isScheme('file')) {
    final String packageRoot = p.dirname(
      p.dirname(p.fromUri(nativeLibraryUri)),
    );
    final String host = p.join(packageRoot, 'bin', 'leonard_native_host.dart');
    tried.add(host);
    if (exists(host)) return NativeHostResolution(host, tried);
  }
  for (final String candidate in kNativeHostCwdCandidates) {
    tried.add(candidate);
    if (exists(candidate)) return NativeHostResolution(candidate, tried);
  }
  return NativeHostResolution(null, tried);
}
