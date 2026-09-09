import 'package:glados/glados.dart';
import 'package:leonard_contract/leonard_contract.dart';

const String _lowercase = 'abcdefghijklmnopqrstuvwxyz';
const String _tokenTail = '${_lowercase}0123456789_';

final Generator<String> _tokenHead = any.choose<String>(_lowercase.split(''));

final Generator<String> _validNamespace = any.combine2(
  _tokenHead,
  any.stringOf(_tokenTail),
  (String head, String tail) => '$head$tail',
);

final Generator<String> _bareTool = any.combine2(
  _tokenHead,
  any.stringOf(_tokenTail),
  (String head, String tail) => '$head$tail',
);

final Generator<String> _invalidNamespace = any.combine2(
  _validNamespace,
  any.intInRange(0, 6),
  (String namespace, int variant) => switch (variant) {
    0 => '',
    1 => namespace.toUpperCase(),
    2 => '0$namespace',
    3 => '_$namespace',
    4 => '$namespace-',
    _ => '$namespace.$namespace',
  },
);

final Generator<String> _dottedTool = any.combine2(
  _bareTool,
  _bareTool,
  (String first, String second) => '$first.$second',
);

class _Tool extends LeonardTool {
  const _Tool(this.name);

  @override
  final String name;

  @override
  String get description => 'generated tool $name';

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{});

  @override
  Future<ToolResult> call(Map<String, Object?> args) async =>
      const ToolResult(ok: true);
}

class _Extension extends LeonardExtension {
  _Extension(this.namespace, List<String> toolNames)
    : tools = <LeonardTool>[
        for (final String toolName in toolNames) _Tool(toolName),
      ];

  @override
  String namespace;

  @override
  final List<LeonardTool> tools;

  @override
  Future<void> initialize(ExtensionContext ctx) async {}

  @override
  Future<BusyState> busyState() async => BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {}
}

class _ExtensionSpec {
  const _ExtensionSpec(this.namespace, this.tools);

  final String namespace;
  final List<String> tools;
}

final Generator<_ExtensionSpec> _extensionSpec = any.combine2(
  _validNamespace,
  any.listWithLengthInRange<String>(0, 6, _bareTool),
  (String namespace, List<String> tools) => _ExtensionSpec(namespace, tools),
);

List<_ExtensionSpec> _retainDistinct(List<_ExtensionSpec> candidates) {
  final Set<String> namespaces = <String>{};
  final List<_ExtensionSpec> result = <_ExtensionSpec>[];

  for (final _ExtensionSpec candidate in candidates) {
    if (!namespaces.add(candidate.namespace)) {
      continue;
    }
    final Set<String> toolNames = <String>{};
    result.add(
      _ExtensionSpec(candidate.namespace, <String>[
        for (final String tool in candidate.tools)
          if (toolNames.add(tool)) tool,
      ]),
    );
  }

  return result;
}

final Generator<List<_ExtensionSpec>> _distinctExtensionSpecs = any
    .listWithLengthInRange<_ExtensionSpec>(0, 9, _extensionSpec)
    .map<List<_ExtensionSpec>>(_retainDistinct);

void main() {
  Glados<List<_ExtensionSpec>>(_distinctExtensionSpecs).test(
    'preserves registration order and merges exactly every qualified tool',
    (List<_ExtensionSpec> specs) {
      final ExtensionRegistry registry = ExtensionRegistry();
      for (final _ExtensionSpec spec in specs) {
        registry.register(_Extension(spec.namespace, spec.tools));
      }

      final List<String> expectedNamespaces = <String>[
        for (final _ExtensionSpec spec in specs) spec.namespace,
      ];
      final List<List<String>> expectedManifestTools = <List<String>>[
        for (final _ExtensionSpec spec in specs) spec.tools,
      ];
      final List<String> expectedMergedKeys = <String>[
        for (final _ExtensionSpec spec in specs)
          for (final String tool in spec.tools) '${spec.namespace}.$tool',
      ];

      expect(registry.namespaces, expectedNamespaces);
      expect(
        registry.manifest
            .map(
              (({String namespace, List<String> tools}) entry) =>
                  entry.namespace,
            )
            .toList(),
        expectedNamespaces,
      );
      expect(
        registry.manifest
            .map(
              (({String namespace, List<String> tools}) entry) => entry.tools,
            )
            .toList(),
        expectedManifestTools,
      );
      expect(registry.mergedTools().keys.toList(), expectedMergedKeys);
    },
  );

  Glados<String>(_validNamespace).test('rejects duplicate namespaces', (
    String namespace,
  ) {
    final ExtensionRegistry registry = ExtensionRegistry();
    registry.register(_Extension(namespace, const <String>[]));

    expect(
      () => registry.register(_Extension(namespace, const <String>[])),
      throwsStateError,
    );
  });

  Glados<String>(_invalidNamespace).test('rejects every invalid namespace', (
    String namespace,
  ) {
    expect(
      () =>
          ExtensionRegistry().register(_Extension(namespace, const <String>[])),
      throwsArgumentError,
    );
  });

  Glados2<String, String>(_validNamespace, _dottedTool).test(
    'rejects dotted tool names',
    (String namespace, String dottedTool) {
      final ExtensionRegistry registry = ExtensionRegistry();
      registry.register(_Extension(namespace, <String>[dottedTool]));

      expect(registry.mergedTools, throwsArgumentError);
    },
  );

  Glados2<String, String>(_validNamespace, _bareTool).test(
    'rejects duplicate tools within an extension',
    (String namespace, String tool) {
      final ExtensionRegistry registry = ExtensionRegistry();
      registry.register(_Extension(namespace, <String>[tool, tool]));

      expect(registry.mergedTools, throwsStateError);
    },
  );

  Glados2<String, String>(_validNamespace, _bareTool).test(
    'rejects qualified collisions between mutable extensions',
    (String firstNamespace, String tool) {
      final String secondNamespace = '${firstNamespace}x';
      final _Extension first = _Extension(firstNamespace, <String>[tool]);
      final _Extension second = _Extension(secondNamespace, <String>[tool]);
      final ExtensionRegistry registry = ExtensionRegistry();
      registry
        ..register(first)
        ..register(second);

      first.namespace = secondNamespace;

      expect(registry.mergedTools, throwsStateError);
    },
  );

  Glados<String>(_validNamespace).test('rejects registration after finalize', (
    String namespace,
  ) {
    final ExtensionRegistry registry = ExtensionRegistry();
    registry.register(_Extension(namespace, const <String>[]));
    registry.finalize();

    expect(
      () => registry.register(_Extension('${namespace}x', const <String>[])),
      throwsStateError,
    );
  });
}
