import 'dart:convert';

import 'package:glados/glados.dart';
import 'package:leonard_contract/leonard_contract.dart';

const String _textAlphabet = 'abcXYZ019 \t\n\r"\\{}[],:.-+';

final Generator<String> _text = any.stringOf(_textAlphabet);

final Generator<Object?> _jsonScalar = any.oneOf<Object?>(<Generator<Object?>>[
  any.always<Object?>(null),
  any.bool.map<Object?>((bool value) => value),
  any.intInRange(-1000, 1001).map<Object?>((int value) => value),
  any.doubleInRange(-1000, 1000).map<Object?>((double value) => value),
  _text.map<Object?>((String value) => value),
]);

Generator<Object?> _jsonList(Generator<Object?> element) => any
    .listWithLengthInRange<Object?>(0, 5, element)
    .map<Object?>((List<Object?> value) => value);

Generator<Object?> _jsonMap(Generator<Object?> value) => any
    .listWithLengthInRange<MapEntry<String, Object?>>(
      0,
      5,
      any.mapEntry<String, Object?>(_text, value),
    )
    .map<Object?>(
      (List<MapEntry<String, Object?>> entries) =>
          Map<String, Object?>.fromEntries(entries),
    );

final Generator<Object?> _jsonLevelOne = any.oneOf<Object?>(
  <Generator<Object?>>[
    _jsonScalar,
    _jsonList(_jsonScalar),
    _jsonMap(_jsonScalar),
  ],
);

final Generator<Object?> _jsonValue = any.oneOf<Object?>(<Generator<Object?>>[
  _jsonScalar,
  _jsonList(_jsonLevelOne),
  _jsonMap(_jsonLevelOne),
]);

final Generator<String?> _nullableError = any.oneOf<String?>(
  <Generator<String?>>[
    any.always<String?>(null),
    _text.map<String?>((String value) => value),
  ],
);

class _ResultSpec {
  const _ResultSpec({required this.ok, required this.value, this.error});

  final bool ok;
  final Object? value;
  final String? error;
}

final Generator<_ResultSpec> _resultSpec = any.combine3(
  any.bool,
  _jsonValue,
  _nullableError,
  (bool ok, Object? value, String? error) =>
      _ResultSpec(ok: ok, value: value, error: error),
);

final Generator<Object> _throwable = any.oneOf<Object>(<Generator<Object>>[
  _text.map<Object>((String value) => value),
  any.bool.map<Object>((bool value) => value),
  any.intInRange(-1000, 1001).map<Object>((int value) => value),
  any.doubleInRange(-1000, 1000).map<Object>((double value) => value),
  _text.map<Object>((String value) => StateError(value)),
  _text.map<Object>((String value) => ArgumentError.value(value)),
]);

class _ReturningTool extends LeonardTool {
  const _ReturningTool(this.result);

  final ToolResult result;

  @override
  String get name => 'returning';

  @override
  String get description => 'returns a generated result';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{});

  @override
  Future<ToolResult> call(Map<String, Object?> args) async => result;
}

class _ThrowingTool extends LeonardTool {
  const _ThrowingTool(this.throwable);

  final Object throwable;

  @override
  String get name => 'throwing';

  @override
  String get description => 'throws a generated object';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{});

  @override
  Future<ToolResult> call(Map<String, Object?> args) {
    Error.throwWithStackTrace(throwable, StackTrace.current);
  }
}

void main() {
  group('decodeServiceExtensionParams', () {
    Glados2<String, Object?>(_text, _jsonValue).test(
      'round-trips JSON-encodable values',
      (String key, Object? value) {
        final Map<String, Object?> decoded = decodeServiceExtensionParams(
          <String, String>{key: jsonEncode(value)},
        );

        expect(decoded, <String, Object?>{key: value});
      },
    );

    Glados<String>(_text).test('passes invalid JSON through unchanged', (
      String raw,
    ) {
      try {
        jsonDecode(raw);
      } on FormatException {
        expect(
          decodeServiceExtensionParams(<String, String>{'key': raw}),
          <String, Object?>{'key': raw},
        );
      }
    });

    Glados<Map<String, String>>(any.map<String, String>(_text, _text)).test(
      'never throws for a map of strings',
      (Map<String, String> params) {
        expect(() => decodeServiceExtensionParams(params), returnsNormally);
      },
    );
  });

  group('dispatchToolToEnvelope', () {
    Glados2<_ResultSpec, bool>(_resultSpec, any.bool).test(
      'preserves returned results and the carry-forward opt-in',
      (_ResultSpec result, bool carryForward) async {
        final ToolResult toolResult = ToolResult(
          ok: result.ok,
          value: result.value,
          error: result.error,
        );
        final Map<String, Object?> envelope =
            jsonDecode(
                  await dispatchToolToEnvelope(
                    _ReturningTool(toolResult),
                    const <String, Object?>{},
                    carryForward: carryForward,
                  ),
                )
                as Map<String, Object?>;

        expect(envelope, <String, Object?>{
          'ok': result.ok,
          'value': result.value,
          'error': result.error,
          if (carryForward) 'carryForward': true,
        });
      },
    );

    Glados<Object>(_throwable).test(
      'catches every thrown object in a failure envelope',
      (Object throwable) async {
        final Map<String, Object?> envelope =
            jsonDecode(
                  await dispatchToolToEnvelope(
                    _ThrowingTool(throwable),
                    const <String, Object?>{},
                    carryForward: true,
                  ),
                )
                as Map<String, Object?>;

        expect(envelope['ok'], isFalse);
        expect(envelope['value'], isNull);
        expect(envelope['error'], isA<String>());
        expect(envelope['error']! as String, startsWith('dispatch_failed:'));
        expect(envelope['trace'], isA<String>());
        expect(envelope['trace']! as String, isNotEmpty);
      },
    );
  });
}
