import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:leonard_grid_assets/leonard_grid_assets.dart';

Future<void> main(List<String> arguments) async {
  final _E2eRunner runner = _E2eRunner()
    ..addCommand(E2eCommand(out: stdout, err: stderr));
  try {
    exitCode = await runner.run(arguments) ?? 64;
  } on UsageException catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  }
}

class _E2eRunner extends CommandRunner<int> {
  _E2eRunner() : super('leonard_grid_assets', 'Leonard grid asset tools.');

  @override
  void printUsage() => stderr.writeln(usage);
}
