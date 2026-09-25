import 'package:leonard_cli/src/native_host_resolution.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final String pubCacheRoot = p.join(
    p.separator,
    'pub-cache',
    'hosted',
    'pub.dev',
    'leonard_native-0.4.1',
  );
  final Uri hostedLibrary = p.toUri(
    p.join(pubCacheRoot, 'lib', 'leonard_native.dart'),
  );
  final String hostedHost = p.join(
    pubCacheRoot,
    'bin',
    'leonard_native_host.dart',
  );

  group('resolveNativeHost', () {
    test('finds the host through the package config (a hosted install)', () {
      final NativeHostResolution r = resolveNativeHost(
        nativeLibraryUri: hostedLibrary,
        exists: (String path) => path == hostedHost,
      );
      expect(r.path, hostedHost);
      expect(r.tried, <String>[hostedHost]);
    });

    test('falls back to the in-repo working-directory candidates', () {
      final NativeHostResolution r = resolveNativeHost(
        nativeLibraryUri: null,
        exists: (String path) =>
            path == 'packages/leonard_native/bin/leonard_native_host.dart',
      );
      expect(r.path, 'packages/leonard_native/bin/leonard_native_host.dart');
      expect(r.tried, kNativeHostCwdCandidates);
    });

    test('a package-config miss still tries the working directory', () {
      final NativeHostResolution r = resolveNativeHost(
        nativeLibraryUri: hostedLibrary,
        exists: (String path) => path == 'bin/leonard_native_host.dart',
      );
      expect(r.path, 'bin/leonard_native_host.dart');
      expect(r.tried, <String>[hostedHost, 'bin/leonard_native_host.dart']);
    });

    test('an all-miss returns null and every path it tried', () {
      final NativeHostResolution r = resolveNativeHost(
        nativeLibraryUri: hostedLibrary,
        exists: (String path) => false,
      );
      expect(r.path, isNull);
      expect(r.tried, <String>[hostedHost, ...kNativeHostCwdCandidates]);
    });

    test('a non-file package URI is not treated as a package root', () {
      final NativeHostResolution r = resolveNativeHost(
        nativeLibraryUri: Uri.parse(
          'package:leonard_native/leonard_native.dart',
        ),
        exists: (String path) => false,
      );
      expect(r.path, isNull);
      expect(r.tried, kNativeHostCwdCandidates);
    });
  });
}
