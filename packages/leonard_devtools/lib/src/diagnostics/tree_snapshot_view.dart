import 'package:flutter/material.dart';
import 'package:genesis_foundation/genesis_foundation.dart';

/// An interactive master-detail renderer for a diagnostics snapshot.
class TreeSnapshotView extends StatefulWidget {
  const TreeSnapshotView({super.key, required this.snapshot});
  final TreeSnapshot snapshot;

  @override
  State<TreeSnapshotView> createState() => _TreeSnapshotViewState();
}

class _TreeSnapshotViewState extends State<TreeSnapshotView> {
  late String _selectedId = widget.snapshot.root.id;
  final Set<String> _expandedIds = <String>{};

  @override
  void didUpdateWidget(covariant TreeSnapshotView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_findNode(widget.snapshot.root, _selectedId) == null) {
      _selectedId = widget.snapshot.root.id;
    }
    _expandedIds.removeWhere(
      (String id) => _findNode(widget.snapshot.root, id) == null,
    );
  }

  TreeNode? _findNode(TreeNode node, String id) {
    if (node.id == id) return node;
    for (final TreeNode child in node.children) {
      final TreeNode? found = _findNode(child, id);
      if (found != null) return found;
    }
    return null;
  }

  void _flatten(TreeNode node, int depth, List<(TreeNode, int)> output) {
    output.add((node, depth));
    if (_expandedIds.contains(node.id)) {
      for (final TreeNode child in node.children) {
        _flatten(child, depth + 1, output);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<(TreeNode, int)> visible = <(TreeNode, int)>[];
    _flatten(widget.snapshot.root, 0, visible);
    final TreeNode selected =
        _findNode(widget.snapshot.root, _selectedId) ?? widget.snapshot.root;
    return Material(
      child: Row(
        children: <Widget>[
          Expanded(
            child: ListView(
              children: <Widget>[
                for (final (TreeNode node, int depth) in visible)
                  ListTile(
                    key: Key('diagnostics.node.${node.id}'),
                    selected: node.id == selected.id,
                    contentPadding: EdgeInsets.only(left: 12.0 + depth * 20),
                    leading: node.children.isEmpty
                        ? const Icon(Icons.circle, size: 8)
                        : IconButton(
                            icon: Icon(
                              _expandedIds.contains(node.id)
                                  ? Icons.expand_more
                                  : Icons.chevron_right,
                            ),
                            onPressed: () => setState(() {
                              _expandedIds.contains(node.id)
                                  ? _expandedIds.remove(node.id)
                                  : _expandedIds.add(node.id);
                            }),
                          ),
                    title: Text(node.seedType),
                    subtitle: Text(node.id),
                    onTap: () => setState(() => _selectedId = node.id),
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _Details(node: selected)),
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.node});
  final TreeNode node;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      Text(node.seedType, key: const Key('diagnostics.details.seedType')),
      SelectableText(node.id, key: const Key('diagnostics.details.id')),
      if (node.key case final String key) SelectableText('key: $key'),
      for (final DiagnosticsProperty property in node.properties)
        _PropertyRow(property: property, depth: 0),
    ],
  );
}

class _PropertyRow extends StatelessWidget {
  const _PropertyRow({required this.property, required this.depth});
  final DiagnosticsProperty property;
  final int depth;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: depth * 16.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              diagnosticsLevelIcon(property.level),
              color: diagnosticsLevelColor(context, property.level),
              size: 16,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${property.name}: ${diagnosticsPropertyValue(property)}',
              ),
            ),
          ],
        ),
        if (property case DiagnosticsObjectProperty(:final properties))
          for (final DiagnosticsProperty child in properties)
            _PropertyRow(property: child, depth: depth + 1),
      ],
    ),
  );
}

/// Formats the value carried by every diagnostics property variant.
String diagnosticsPropertyValue(
  DiagnosticsProperty property,
) => switch (property) {
  DiagnosticsStringProperty(:final value) => value,
  DiagnosticsIntProperty(:final value) => '$value',
  DiagnosticsDoubleProperty(:final value) => '$value',
  DiagnosticsFlagProperty(:final value) => '$value',
  DiagnosticsEnumProperty(:final enumType, :final value) => '$enumType.$value',
  DiagnosticsDurationProperty(:final value) => value.toString(),
  DiagnosticsTimestampProperty(:final value) => value.toUtc().toIso8601String(),
  DiagnosticsReferenceProperty(:final referenceKind, :final value) =>
    '${referenceKind.name}:$value',
  DiagnosticsObjectProperty(:final properties) =>
    '${properties.length} properties',
};

/// Chooses the Material icon for a diagnostics severity.
IconData diagnosticsLevelIcon(DiagnosticsLevel level) => switch (level) {
  DiagnosticsLevel.fine => Icons.tune,
  DiagnosticsLevel.info => Icons.info_outline,
  DiagnosticsLevel.warning => Icons.warning_amber,
  DiagnosticsLevel.error => Icons.error_outline,
};

/// Chooses a theme-aware color for a diagnostics severity.
Color diagnosticsLevelColor(BuildContext context, DiagnosticsLevel level) =>
    switch (level) {
      DiagnosticsLevel.fine => Theme.of(context).colorScheme.outline,
      DiagnosticsLevel.info => Theme.of(context).colorScheme.primary,
      DiagnosticsLevel.warning => Colors.orange,
      DiagnosticsLevel.error => Theme.of(context).colorScheme.error,
    };
