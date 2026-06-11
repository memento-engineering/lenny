import 'package:perception/perception.dart';
import 'package:test/test.dart';

class _Tagged extends Perception {
  const _Tagged(this.tag, {super.key});
  final String tag;
  @override
  _TaggedElement createElement() => _TaggedElement(this);
}

class _TaggedElement extends PerceptionElement {
  _TaggedElement(super.p);
}

void main() {
  group('Node construction', () {
    test('createElement returns NodeElement', () {
      expect(const Node('n').createElement(), isA<NodeElement>());
    });

    test('name and children stored', () {
      const c = _Tagged('x');
      final n = Node('root', children: [c]);
      expect(n.name, equals('root'));
      expect(n.children, equals([c]));
    });

    test('default children is empty', () {
      expect(const Node('n').children, isEmpty);
    });
  });

  group('NodeElement mount', () {
    test('empty node mounts with no children', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el = owner.mountRoot(const Node('root')) as NodeElement;
      expect(el.mounted, isTrue);
      expect(el.children, isEmpty);
    });

    test('children are mounted on root mount', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el = owner.mountRoot(Node('root', children: [
        const _Tagged('a'),
        const _Tagged('b'),
      ])) as NodeElement;
      expect(el.children.length, equals(2));
      expect(el.children.every((c) => c.mounted), isTrue);
    });

    test('children receive distinct perceptionIds', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el = owner.mountRoot(Node('root', children: [
        const _Tagged('a'),
        const _Tagged('b'),
      ])) as NodeElement;
      expect(el.children[0].perceptionId, isNotEmpty);
      expect(
        el.children[0].perceptionId,
        isNot(equals(el.children[1].perceptionId)),
      );
    });
  });

  group('NodeElement update — keyed identity', () {
    test('keyed child identity preserved after reorder', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el = owner.mountRoot(Node('root', children: [
        const _Tagged('a', key: 'ka'),
        const _Tagged('b', key: 'kb'),
      ])) as NodeElement;

      final idA = el.children[0].perceptionId;
      final idB = el.children[1].perceptionId;

      el.update(Node('root', children: [
        const _Tagged('b', key: 'kb'),
        const _Tagged('a', key: 'ka'),
      ]));

      expect(el.children[0].perceptionId, equals(idB));
      expect(el.children[1].perceptionId, equals(idA));
      expect(el.children.every((c) => c.mounted), isTrue);
    });

    test('removed keyed child is unmounted', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el = owner.mountRoot(Node('root', children: [
        const _Tagged('a', key: 'ka'),
        const _Tagged('b', key: 'kb'),
      ])) as NodeElement;

      final removed = el.children[1];
      el.update(Node('root', children: [const _Tagged('a', key: 'ka')]));

      expect(el.children.length, equals(1));
      expect(removed.mounted, isFalse);
    });

    test('new keyed child is freshly mounted', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el = owner.mountRoot(Node('root', children: [
        const _Tagged('a', key: 'ka'),
      ])) as NodeElement;

      el.update(Node('root', children: [
        const _Tagged('a', key: 'ka'),
        const _Tagged('b', key: 'kb'),
      ]));

      expect(el.children.length, equals(2));
      expect(el.children[1].mounted, isTrue);
      expect(el.children[1].perceptionId, isNotEmpty);
    });
  });

  group('NodeElement update — unkeyed identity', () {
    test('unkeyed positional identity preserved across update', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el = owner.mountRoot(Node('root', children: [
        const _Tagged('a'),
        const _Tagged('b'),
      ])) as NodeElement;

      final id0 = el.children[0].perceptionId;
      final id1 = el.children[1].perceptionId;

      el.update(Node('root', children: [
        const _Tagged('x'),
        const _Tagged('y'),
      ]));

      expect(el.children[0].perceptionId, equals(id0));
      expect(el.children[1].perceptionId, equals(id1));
    });

    test('unkeyed excess child at tail is unmounted', () {
      final owner = PerceptionOwner();
      addTearDown(owner.dispose);
      final el = owner.mountRoot(Node('root', children: [
        const _Tagged('a'),
        const _Tagged('b'),
      ])) as NodeElement;

      final removed = el.children[1];
      el.update(Node('root', children: [const _Tagged('a')]));

      expect(el.children.length, equals(1));
      expect(removed.mounted, isFalse);
    });
  });

  group('NodeElement unmount', () {
    test('all children unmounted when node unmounts', () {
      final owner = PerceptionOwner();
      final el = owner.mountRoot(Node('root', children: [
        const _Tagged('a', key: 'ka'),
        const _Tagged('b', key: 'kb'),
      ])) as NodeElement;
      final c0 = el.children[0];
      final c1 = el.children[1];

      owner.unmountRoot();

      expect(c0.mounted, isFalse);
      expect(c1.mounted, isFalse);
    });
  });
}
