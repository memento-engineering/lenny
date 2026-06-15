import 'dart:io';

import 'package:leonard_cli/src/run.dart';

Future<void> main(List<String> args) async {
  exitCode = await runCli(
    args,
    stdin: stdin,
    stdout: stdout,
    stderr: stderr,
  );
}
