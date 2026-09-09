import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../integration_test/support/dual_e2e_target.dart';

void main() {
  final String packageRoot = p.join('workspace', 'packages', 'leonard_cli');
  final String sampleProject = p.join(
    'workspace',
    'packages',
    'leonard_flutter',
    'example',
    'sample_app',
  );

  test('empty environment defaults to the in-repo sample app', () {
    final DualE2eTarget target = resolveDualE2eTarget(
      packageRoot: packageRoot,
      environment: <String, String>{},
    );

    expect(target.flutterProject, sampleProject);
    expect(
      target.app,
      p.join(sampleProject, 'build', 'ios', 'iphonesimulator', 'Runner.app'),
    );
  });

  test('non-empty environment paths override defaults independently', () {
    const String appOverride = '  fixtures/custom Runner.app  ';
    const String projectOverride = '  fixtures/custom project  ';

    final DualE2eTarget appOnly = resolveDualE2eTarget(
      packageRoot: packageRoot,
      environment: <String, String>{'LEONARD_NATIVE_APP': appOverride},
    );
    expect(appOnly.app, appOverride);
    expect(appOnly.flutterProject, sampleProject);

    final DualE2eTarget projectOnly = resolveDualE2eTarget(
      packageRoot: packageRoot,
      environment: <String, String>{
        'LEONARD_NATIVE_FLUTTER_PROJECT': projectOverride,
      },
    );
    expect(projectOnly.flutterProject, projectOverride);
    expect(
      projectOnly.app,
      p.join(projectOverride, 'build', 'ios', 'iphonesimulator', 'Runner.app'),
    );

    final DualE2eTarget both = resolveDualE2eTarget(
      packageRoot: packageRoot,
      environment: <String, String>{
        'LEONARD_NATIVE_APP': appOverride,
        'LEONARD_NATIVE_FLUTTER_PROJECT': projectOverride,
      },
    );
    expect(both.app, appOverride);
    expect(both.flutterProject, projectOverride);
  });
}
