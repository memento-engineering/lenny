import 'perception.dart';
import 'perception_element.dart';

class Node extends Perception {
  const Node(this.name, {this.children = const [], super.key});

  final String name;
  final List<Perception> children;

  @override
  NodeElement createElement() => NodeElement(this);
}

class NodeElement extends PerceptionElement {
  NodeElement(Node super.perception);

  List<PerceptionElement> _children = const [];

  // Exposed for testing. Do not use in production code.
  List<PerceptionElement> get children => _children;

  Node get _node => perception as Node;

  @override
  void mount(PerceptionElement? parent, Object? slot) {
    super.mount(parent, slot);
    _children = updateChildren(const [], _node.children);
  }

  @override
  void update(Perception newPerception) {
    super.update(newPerception);
    _children = updateChildren(_children, _node.children);
  }

  @override
  void unmount() {
    _children = updateChildren(_children, const []);
    super.unmount();
  }
}
