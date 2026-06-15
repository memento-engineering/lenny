library;

import 'package:genesis_perception/genesis_perception.dart';

Map<String, Object?> serializePerceptionFragment(Branch root) {
  final Branch? node = root is ComponentBranch ? root.child : root;
  if (node is NodeElement) return _serializeNode(node);
  return const <String, Object?>{};
}

Map<String, Object?> _serializeNode(NodeElement element) {
  final Map<String, Object?> result = <String, Object?>{};
  for (final Branch child in element.children) {
    if (child is FieldElement) {
      result[child.field.name] = child.field.value;
    } else if (child is NodeElement) {
      result[(child.perception as Node).name] = _serializeNode(child);
    }
  }
  return result;
}
