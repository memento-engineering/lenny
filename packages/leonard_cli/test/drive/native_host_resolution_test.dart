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
      expect(r.inPackageConfig, isFalse);
    });

    test('records whether the package config resolved leonard_native', () {
      expect(
        resolveNativeHost(
          nativeLibraryUri: hostedLibrary,
          exists: (String path) => path == hostedHost,
        ).inPackageConfig,
        isTrue,
      );
      expect(
        resolveNativeHost(
          nativeLibraryUri: null,
          exists: (String path) => true,
        ).inPackageConfig,
        isFalse,
      );
    });
  });

  group('describeNativeHostMiss (lenny#199)', () {
    test('a null package-config URI with no checkout candidate names the '
        'missing dependency and the fix', () {
      final NativeHostResolution r = resolveNativeHost(
        nativeLibraryUri: null,
        exists: (String path) => false,
      );
      expect(r.path, isNull);
      final String message = describeNativeHostMiss(r);
      expect(message, startsWith('error: '));
      expect(
        message,
        contains(
          "leonard_native is missing from this program's package "
          'config',
        ),
      );
      expect(
        message,
        contains("add leonard_native to your pubspec's dependencies"),
      );
      expect(message, contains('dart pub add leonard_native'));
      expect(message, contains('--native-host'));
      for (final String candidate in kNativeHostCwdCandidates) {
        expect(message, contains(candidate));
      }
    });

    test('a package-config hit without the host script does not blame the '
        'dependency', () {
      final NativeHostResolution r = resolveNativeHost(
        nativeLibraryUri: hostedLibrary,
        exists: (String path) => false,
      );
      final String message = describeNativeHostMiss(r);
      expect(message, isNot(contains('missing from')));
      expect(message, contains('resolves through the package config'));
      expect(message, contains(hostedHost));
      expect(message, contains('--native-host'));
    });
  });
}
