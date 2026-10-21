/// Leonard's `initialize` capabilities, pinned on the wire.
library;

import 'dart:convert';

import 'package:leonard_acp/leonard_acp.dart';
import 'package:test/test.dart';

void main() {
  test('advertises fs as an all-false object, never null', () {
    // The Copilot CLI rejects initialize with -32602 when fs is null.
    final Map<String, Object?> wire =
        jsonDecode(jsonEncode(leonardClientCapabilities().toJson()))
            as Map<String, Object?>;
    expect(wire['fs'], <String, Object?>{
      'readTextFile': false,
      'writeTextFile': false,
    });
    expect(wire['terminal'], isFalse);
  });
}
