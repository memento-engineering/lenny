import 'package:leonard_agent/leonard_agent.dart';

/// Resolves exact `${NAME}` string arguments immediately before dispatch.
///
/// The model prompt and trajectory retain the placeholder. Only the delegated
/// target call receives the environment value, so credentials never enter the
/// model conversation or persisted [TurnRecord].
class ActionEnvironmentLoopHost implements LoopHost {
  ActionEnvironmentLoopHost({
    required LoopHost delegate,
    required Map<String, String> valuesByName,
  }) : _delegate = delegate,
       _valuesByName = Map<String, String>.unmodifiable(valuesByName);

  static final RegExp _placeholder = RegExp(r'^\$\{([A-Z][A-Z0-9_]*)\}$');

  final LoopHost _delegate;
  final Map<String, String> _valuesByName;

  @override
  String get agentsMd => _delegate.agentsMd;

  @override
  String get goal => _delegate.goal;

  @override
  Future<Observation> observe() => _delegate.observe();

  @override
  Future<Map<String, dynamic>> executeAction(
    String tool,
    Map<String, dynamic> args,
  ) => _delegate.executeAction(tool, _resolveMap(args));

  @override
  Future<void> notifyExtensions(
    String tool,
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  ) => _delegate.notifyExtensions(tool, _resolveMap(args), result);

  @override
  void disableExtension(String namespace, String reason) =>
      _delegate.disableExtension(namespace, reason);

  @override
  List<ToolDescriptor> mergedTools() => _delegate.mergedTools();

  @override
  Set<String> activeExtensionNamespaces() =>
      _delegate.activeExtensionNamespaces();

  Map<String, dynamic> _resolveMap(Map<String, dynamic> value) =>
      <String, dynamic>{
        for (final MapEntry<String, dynamic> entry in value.entries)
          entry.key: _resolve(entry.value),
      };

  Object? _resolve(Object? value) => switch (value) {
    String text => _resolveString(text),
    List<dynamic> values => <Object?>[
      for (final Object? entry in values) _resolve(entry),
    ],
    Map<dynamic, dynamic> values => <String, dynamic>{
      for (final MapEntry<dynamic, dynamic> entry in values.entries)
        entry.key as String: _resolve(entry.value),
    },
    _ => value,
  };

  String _resolveString(String text) {
    final RegExpMatch? match = _placeholder.firstMatch(text);
    if (match == null) return text;
    return _valuesByName[match.group(1)] ?? text;
  }
}
