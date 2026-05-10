/// Per-provider configuration value types + form widget for the
/// DevTools prompt panel.
///
/// The value types ([ProviderConfig] + variants) are sealed so the
/// panel + builder code can switch exhaustively. Secrets (api keys,
/// bearer tokens) live in private fields and are NEVER surfaced via
/// [toString] or [toJsonRedacted]. The unredacted [toJson] is for
/// local persistence only and is documented as such.
library;

import 'package:flutter/material.dart';

import 'model_catalog.dart';

/// Sealed configuration for one provider — swift-infer / anthropic /
/// openai.
///
/// All variants expose:
///   - [id] — stable provider id (`'swift-infer' | 'anthropic' | 'openai'`).
///   - [defaultModelId] — the model id the panel pre-selects + the
///     swift-infer fallback model id if `/v1/models` is missing.
///   - [baseUrl] — the URL the [ModelCatalog] hits.
///   - [headersFor] — outgoing headers for the catalog request, given
///     the active conversation id (some providers ignore it).
///   - [toJson] — full state for persistence (INCLUDES the secret —
///     persistence is local-only).
///   - [toJsonRedacted] — safe to log/display; never includes the
///     secret.
sealed class ProviderConfig {
  const ProviderConfig();

  /// Stable provider id used by [capabilitiesFor] and the build
  /// switch.
  String get id;

  /// Pre-selected model in the panel dropdown and the swift-infer
  /// fallback model id when `/v1/models` is not implemented.
  String get defaultModelId;

  /// Base URL for `/v1/models` + `/v1/messages`.
  Uri get baseUrl;

  /// Outgoing headers for [ModelCatalog]. Per-conversation headers
  /// (swift-infer's `X-Conversation-Id`) are seeded from
  /// [conversationId].
  Map<String, String> headersFor(String conversationId);

  /// Full state for persistence. **Includes secrets** — never log this
  /// map and never round-trip it across an untrusted boundary.
  Map<String, dynamic> toJson();

  /// Same shape as [toJson] but with the secret replaced by
  /// `'<redacted>'`. Safe to log / surface in the UI.
  Map<String, dynamic> toJsonRedacted();

  /// Decode from [toJson] output. Used by [ProviderConfigStore].
  static ProviderConfig fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    switch (id) {
      case 'swift-infer':
        return SwiftInferUiConfig._fromJson(json);
      case 'anthropic':
        return AnthropicUiConfig._fromJson(json);
      case 'openai':
        return OpenAiUiConfig._fromJson(json);
      default:
        throw ArgumentError('unknown provider id: $id');
    }
  }
}

/// swift-infer panel configuration.
///
/// Mirrors `SwiftInferConfig`'s wire contract:
///   - [bearerToken] → `Authorization: Bearer <token>` (matches
///     `SWIFT_INFER_AGENT_TOKEN` in `fs agent`).
///   - [endpoint] is the gateway base URL.
///   - [captureBodies] → `X-Swift-Infer-Capture-Bodies: true` so the
///     gateway persists request/response for
///     `GET /v1/conversations/<id>` introspection.
///   - [extraHeaders] are merged in FIRST; the four well-known headers
///     overwrite — they always win on conflict.
class SwiftInferUiConfig extends ProviderConfig {
  SwiftInferUiConfig({
    required String bearerToken,
    required this.endpoint,
    this.captureBodies = true,
    this.extraHeaders = const <String, String>{},
    this.defaultModelId = 'qwen3.6-35b-a3b-8bit',
  }) : _bearerToken = bearerToken;

  @override
  String get id => 'swift-infer';

  /// Bearer token (private — never logged or stringified).
  final String _bearerToken;

  /// Read access for the request builder and the form widget. NEVER
  /// surface this value through [toString]/[toJsonRedacted].
  String get bearerToken => _bearerToken;

  /// swift-infer gateway base URL (e.g. `http://localhost:8080`).
  final Uri endpoint;

  /// When `true`, sends `X-Swift-Infer-Capture-Bodies: true`.
  final bool captureBodies;

  /// Forward-compat header bag. Merged into requests FIRST so the
  /// four well-known swift-infer headers always win on conflict.
  final Map<String, String> extraHeaders;

  @override
  final String defaultModelId;

  @override
  Uri get baseUrl => endpoint;

  @override
  Map<String, String> headersFor(String conversationId) {
    final h = <String, String>{}..addAll(extraHeaders);
    // Well-known headers overwrite anything in extraHeaders.
    h['content-type'] = 'application/json';
    h['accept'] = 'application/json';
    if (_bearerToken.isNotEmpty) {
      h['authorization'] = 'Bearer $_bearerToken';
    }
    if (captureBodies) {
      h['x-swift-infer-capture-bodies'] = 'true';
    }
    if (conversationId.isNotEmpty) {
      h['x-conversation-id'] = conversationId;
    }
    return h;
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'bearerToken': _bearerToken,
        'endpoint': endpoint.toString(),
        'captureBodies': captureBodies,
        'extraHeaders': extraHeaders,
        'defaultModelId': defaultModelId,
      };

  @override
  Map<String, dynamic> toJsonRedacted() => <String, dynamic>{
        'id': id,
        'bearerToken': '<redacted>',
        'endpoint': endpoint.toString(),
        'captureBodies': captureBodies,
        'extraHeaders': extraHeaders,
        'defaultModelId': defaultModelId,
      };

  @override
  String toString() => 'SwiftInferUiConfig(${toJsonRedacted()})';

  static SwiftInferUiConfig _fromJson(Map<String, dynamic> json) =>
      SwiftInferUiConfig(
        bearerToken: (json['bearerToken'] as String?) ?? '',
        endpoint: Uri.parse(json['endpoint'] as String),
        captureBodies: (json['captureBodies'] as bool?) ?? true,
        extraHeaders: ((json['extraHeaders'] as Map?) ?? const <String, String>{})
            .cast<String, String>(),
        defaultModelId:
            (json['defaultModelId'] as String?) ?? 'qwen3.6-35b-a3b-8bit',
      );
}

/// Anthropic panel configuration.
class AnthropicUiConfig extends ProviderConfig {
  AnthropicUiConfig({
    required String apiKey,
    this.baseUrlOverride,
    this.defaultModelId = 'claude-sonnet-4-6',
  }) : _apiKey = apiKey;

  @override
  String get id => 'anthropic';

  final String _apiKey;

  /// Read access for the request builder and form. NEVER surface via
  /// [toString]/[toJsonRedacted].
  String get apiKey => _apiKey;

  /// Optional base URL override (defaults to `https://api.anthropic.com`).
  final Uri? baseUrlOverride;

  @override
  final String defaultModelId;

  @override
  Uri get baseUrl => baseUrlOverride ?? Uri.parse('https://api.anthropic.com');

  @override
  Map<String, String> headersFor(String conversationId) => <String, String>{
        'content-type': 'application/json',
        'accept': 'application/json',
        'x-api-key': _apiKey,
        'anthropic-version': '2023-06-01',
      };

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'apiKey': _apiKey,
        'baseUrlOverride': baseUrlOverride?.toString(),
        'defaultModelId': defaultModelId,
      };

  @override
  Map<String, dynamic> toJsonRedacted() => <String, dynamic>{
        'id': id,
        'apiKey': '<redacted>',
        'baseUrlOverride': baseUrlOverride?.toString(),
        'defaultModelId': defaultModelId,
      };

  @override
  String toString() => 'AnthropicUiConfig(${toJsonRedacted()})';

  static AnthropicUiConfig _fromJson(Map<String, dynamic> json) =>
      AnthropicUiConfig(
        apiKey: (json['apiKey'] as String?) ?? '',
        baseUrlOverride: json['baseUrlOverride'] == null
            ? null
            : Uri.parse(json['baseUrlOverride'] as String),
        defaultModelId:
            (json['defaultModelId'] as String?) ?? 'claude-sonnet-4-6',
      );
}

/// OpenAI panel configuration.
class OpenAiUiConfig extends ProviderConfig {
  OpenAiUiConfig({
    required String apiKey,
    this.baseUrlOverride,
    this.defaultModelId = 'gpt-5',
  }) : _apiKey = apiKey;

  @override
  String get id => 'openai';

  final String _apiKey;

  /// Read access for the request builder and form. NEVER surface via
  /// [toString]/[toJsonRedacted].
  String get apiKey => _apiKey;

  /// Optional base URL override (defaults to `https://api.openai.com`).
  final Uri? baseUrlOverride;

  @override
  final String defaultModelId;

  @override
  Uri get baseUrl => baseUrlOverride ?? Uri.parse('https://api.openai.com');

  @override
  Map<String, String> headersFor(String conversationId) => <String, String>{
        'content-type': 'application/json',
        'accept': 'application/json',
        'authorization': 'Bearer $_apiKey',
      };

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'apiKey': _apiKey,
        'baseUrlOverride': baseUrlOverride?.toString(),
        'defaultModelId': defaultModelId,
      };

  @override
  Map<String, dynamic> toJsonRedacted() => <String, dynamic>{
        'id': id,
        'apiKey': '<redacted>',
        'baseUrlOverride': baseUrlOverride?.toString(),
        'defaultModelId': defaultModelId,
      };

  @override
  String toString() => 'OpenAiUiConfig(${toJsonRedacted()})';

  static OpenAiUiConfig _fromJson(Map<String, dynamic> json) => OpenAiUiConfig(
        apiKey: (json['apiKey'] as String?) ?? '',
        baseUrlOverride: json['baseUrlOverride'] == null
            ? null
            : Uri.parse(json['baseUrlOverride'] as String),
        defaultModelId: (json['defaultModelId'] as String?) ?? 'gpt-5',
      );
}

// ===========================================================================
// Form widget — implemented in step 5; declared here so step 6's prompt
// panel can import the symbol without forward-reference noise.
// ===========================================================================

/// Per-provider configuration form. Built in step 5.
class ProviderConfigForm extends StatefulWidget {
  const ProviderConfigForm({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.conversationId,
    required this.catalog,
  });

  /// Starting config. `null` means the panel has never been configured
  /// — the form initialises with empty fields and the swift-infer
  /// preset.
  final ProviderConfig? initial;

  /// Fires when any field changes — parent persists.
  final void Function(ProviderConfig) onChanged;

  /// Read-only conversation id breadcrumb (swift-infer only).
  final String conversationId;

  /// Used by the "Test connection" button to call
  /// [ModelCatalog.fetch] with `reload: true`.
  final ModelCatalog catalog;

  @override
  State<ProviderConfigForm> createState() => _ProviderConfigFormState();
}

class _ProviderConfigFormState extends State<ProviderConfigForm> {
  late ProviderConfig _config = widget.initial ??
      SwiftInferUiConfig(
        bearerToken: '',
        endpoint: Uri.parse('http://localhost:8080'),
      );
  String? _testResult;
  bool _testLoading = false;

  void _replace(ProviderConfig next) {
    setState(() => _config = next);
    widget.onChanged(next);
  }

  void _switchProvider(String? id) {
    if (id == null || id == _config.id) return;
    switch (id) {
      case 'swift-infer':
        _replace(SwiftInferUiConfig(
          bearerToken: '',
          endpoint: Uri.parse('http://localhost:8080'),
        ));
      case 'anthropic':
        _replace(AnthropicUiConfig(apiKey: ''));
      case 'openai':
        _replace(OpenAiUiConfig(apiKey: ''));
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testLoading = true;
      _testResult = null;
    });
    try {
      final models = await widget.catalog.fetch(_config, reload: true);
      if (!mounted) return;
      setState(() => _testResult = 'OK (${models.length} models)');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _testResult = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _testLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DropdownButtonFormField<String>(
          key: const Key('providerForm.providerSelect'),
          initialValue: _config.id,
          decoration: const InputDecoration(labelText: 'Provider'),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem(value: 'swift-infer', child: Text('swift-infer')),
            DropdownMenuItem(value: 'anthropic', child: Text('anthropic')),
            DropdownMenuItem(value: 'openai', child: Text('openai')),
          ],
          onChanged: _switchProvider,
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          child: _buildSubform(),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            ElevatedButton(
              key: const Key('providerForm.testConnection'),
              onPressed: _testLoading ? null : _testConnection,
              child: const Text('Test connection'),
            ),
            const SizedBox(width: 12),
            if (_testResult != null) Text(_testResult!),
          ],
        ),
      ],
    );
  }

  Widget _buildSubform() {
    final cfg = _config;
    if (cfg is SwiftInferUiConfig) {
      return _SwiftInferSubform(
        key: const Key('providerForm.swift-infer'),
        config: cfg,
        conversationId: widget.conversationId,
        onChanged: _replace,
      );
    }
    if (cfg is AnthropicUiConfig) {
      return _AnthropicSubform(
        key: const Key('providerForm.anthropic'),
        config: cfg,
        onChanged: _replace,
      );
    }
    if (cfg is OpenAiUiConfig) {
      return _OpenAiSubform(
        key: const Key('providerForm.openai'),
        config: cfg,
        onChanged: _replace,
      );
    }
    return const SizedBox.shrink();
  }
}

class _SwiftInferSubform extends StatefulWidget {
  const _SwiftInferSubform({
    super.key,
    required this.config,
    required this.conversationId,
    required this.onChanged,
  });

  final SwiftInferUiConfig config;
  final String conversationId;
  final void Function(SwiftInferUiConfig) onChanged;

  @override
  State<_SwiftInferSubform> createState() => _SwiftInferSubformState();
}

class _SwiftInferSubformState extends State<_SwiftInferSubform> {
  late final TextEditingController _bearer =
      TextEditingController(text: widget.config.bearerToken);
  late final TextEditingController _endpoint =
      TextEditingController(text: widget.config.endpoint.toString());
  late final TextEditingController _defaultModel =
      TextEditingController(text: widget.config.defaultModelId);
  late bool _captureBodies = widget.config.captureBodies;
  late List<MapEntry<String, String>> _extras =
      widget.config.extraHeaders.entries.toList();

  void _push() {
    widget.onChanged(SwiftInferUiConfig(
      bearerToken: _bearer.text,
      endpoint: Uri.tryParse(_endpoint.text) ?? widget.config.endpoint,
      captureBodies: _captureBodies,
      extraHeaders: Map<String, String>.fromEntries(_extras),
      defaultModelId: _defaultModel.text.isEmpty
          ? widget.config.defaultModelId
          : _defaultModel.text,
    ));
  }

  @override
  void dispose() {
    _bearer.dispose();
    _endpoint.dispose();
    _defaultModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextFormField(
          key: const Key('providerForm.swift-infer.bearer'),
          controller: _bearer,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Bearer token'),
          onChanged: (_) => _push(),
        ),
        TextFormField(
          key: const Key('providerForm.swift-infer.endpoint'),
          controller: _endpoint,
          decoration: const InputDecoration(labelText: 'Endpoint'),
          onChanged: (_) => _push(),
        ),
        TextFormField(
          key: const Key('providerForm.swift-infer.defaultModel'),
          controller: _defaultModel,
          decoration: const InputDecoration(labelText: 'Default model id'),
          onChanged: (_) => _push(),
        ),
        SwitchListTile(
          key: const Key('providerForm.swift-infer.captureBodies'),
          title: const Text('Capture bodies'),
          value: _captureBodies,
          onChanged: (v) {
            setState(() => _captureBodies = v);
            _push();
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SelectableText(
            'conversationId: ${widget.conversationId}',
            key: const Key('providerForm.swift-infer.conversationId'),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 4),
          child: Text('Extra headers'),
        ),
        ..._extras.asMap().entries.map((e) {
          final i = e.key;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    key: Key('providerForm.swift-infer.extra.$i.key'),
                    initialValue: e.value.key,
                    decoration: const InputDecoration(labelText: 'key'),
                    onChanged: (v) {
                      _extras[i] = MapEntry(v, e.value.value);
                      _push();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: Key('providerForm.swift-infer.extra.$i.value'),
                    initialValue: e.value.value,
                    decoration: const InputDecoration(labelText: 'value'),
                    onChanged: (v) {
                      _extras[i] = MapEntry(e.value.key, v);
                      _push();
                    },
                  ),
                ),
                IconButton(
                  key: Key('providerForm.swift-infer.extra.$i.remove'),
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    setState(() => _extras.removeAt(i));
                    _push();
                  },
                ),
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('providerForm.swift-infer.extra.add'),
            onPressed: () {
              setState(() => _extras = <MapEntry<String, String>>[
                    ..._extras,
                    const MapEntry('', ''),
                  ]);
              _push();
            },
            icon: const Icon(Icons.add),
            label: const Text('Add header'),
          ),
        ),
      ],
    );
  }
}

class _AnthropicSubform extends StatefulWidget {
  const _AnthropicSubform({
    super.key,
    required this.config,
    required this.onChanged,
  });

  final AnthropicUiConfig config;
  final void Function(AnthropicUiConfig) onChanged;

  @override
  State<_AnthropicSubform> createState() => _AnthropicSubformState();
}

class _AnthropicSubformState extends State<_AnthropicSubform> {
  late final TextEditingController _key =
      TextEditingController(text: widget.config.apiKey);
  late final TextEditingController _base = TextEditingController(
      text: widget.config.baseUrlOverride?.toString() ?? '');
  late final TextEditingController _defaultModel =
      TextEditingController(text: widget.config.defaultModelId);

  void _push() {
    widget.onChanged(AnthropicUiConfig(
      apiKey: _key.text,
      baseUrlOverride: _base.text.isEmpty ? null : Uri.tryParse(_base.text),
      defaultModelId: _defaultModel.text.isEmpty
          ? widget.config.defaultModelId
          : _defaultModel.text,
    ));
  }

  @override
  void dispose() {
    _key.dispose();
    _base.dispose();
    _defaultModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextFormField(
            key: const Key('providerForm.anthropic.apiKey'),
            controller: _key,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'API key'),
            onChanged: (_) => _push(),
          ),
          TextFormField(
            key: const Key('providerForm.anthropic.baseUrl'),
            controller: _base,
            decoration:
                const InputDecoration(labelText: 'Base URL (optional)'),
            onChanged: (_) => _push(),
          ),
          TextFormField(
            key: const Key('providerForm.anthropic.defaultModel'),
            controller: _defaultModel,
            decoration: const InputDecoration(labelText: 'Default model id'),
            onChanged: (_) => _push(),
          ),
        ],
      );
}

class _OpenAiSubform extends StatefulWidget {
  const _OpenAiSubform({
    super.key,
    required this.config,
    required this.onChanged,
  });

  final OpenAiUiConfig config;
  final void Function(OpenAiUiConfig) onChanged;

  @override
  State<_OpenAiSubform> createState() => _OpenAiSubformState();
}

class _OpenAiSubformState extends State<_OpenAiSubform> {
  late final TextEditingController _key =
      TextEditingController(text: widget.config.apiKey);
  late final TextEditingController _base = TextEditingController(
      text: widget.config.baseUrlOverride?.toString() ?? '');
  late final TextEditingController _defaultModel =
      TextEditingController(text: widget.config.defaultModelId);

  void _push() {
    widget.onChanged(OpenAiUiConfig(
      apiKey: _key.text,
      baseUrlOverride: _base.text.isEmpty ? null : Uri.tryParse(_base.text),
      defaultModelId: _defaultModel.text.isEmpty
          ? widget.config.defaultModelId
          : _defaultModel.text,
    ));
  }

  @override
  void dispose() {
    _key.dispose();
    _base.dispose();
    _defaultModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextFormField(
            key: const Key('providerForm.openai.apiKey'),
            controller: _key,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'API key'),
            onChanged: (_) => _push(),
          ),
          TextFormField(
            key: const Key('providerForm.openai.baseUrl'),
            controller: _base,
            decoration:
                const InputDecoration(labelText: 'Base URL (optional)'),
            onChanged: (_) => _push(),
          ),
          TextFormField(
            key: const Key('providerForm.openai.defaultModel'),
            controller: _defaultModel,
            decoration: const InputDecoration(labelText: 'Default model id'),
            onChanged: (_) => _push(),
          ),
        ],
      );
}
