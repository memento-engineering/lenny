import 'package:flutter/widgets.dart' show runApp;
import 'package:leonard_devtools/main.dart' show LeonardDevToolsExtension;
import 'package:leonard_flutter/leonard_flutter.dart'
    show LeonardBinding, LeonardExtension;

void main() {
  LeonardBinding.ensureInitialized(
    extensions: const <LeonardExtension>[],
  );
  runApp(const LeonardDevToolsExtension());
}
