import 'package:perception/perception.dart';
import 'package:test/test.dart';

class _Leaf extends Perception {
  const _Leaf({super.key});
  @override
  PerceptionElement createElement() => _LeafElement(this);
}

class _LeafElement extends PerceptionElement {
  _LeafElement(super.p);
}

class _Tracker {
  int builds = 0;
  String? lastValue;
}

class _ReadingP extends StatelessPerception {
  _ReadingP(this.tracker, {super.key});
  final _Tracker tracker;
  @override
  Perception build(PerceptionContext ctx) {
    tracker.builds++;
    tracker.lastValue = ctx.dependOnInheritedPerceptionOfExactType<String>();
    return const _Leaf();
  }
}

class _SimpleP extends StatelessPerception {
  const _SimpleP({this.child = const _Leaf(), super.key});
  final Perception child;
  @override
  Perception build(PerceptionContext ctx) => child;
}

void main() {
  test('returns StatelessElement', () {
    expect(_SimpleP().createElement(), isA<StatelessElement>());
  });

  group('ComponentElement child lifecycle', () {
    late PerceptionOwner owner;

    setUp(() {
      owner = PerceptionOwner();
    });
    tearDown(() => owner.dispose());

    test('mounts child on first rebuild', () {
      final el = owner.mountRoot(_SimpleP()) as StatelessElement;
      el.markNeedsHarvest();
      owner.flushHarvest();
      expect(el.child, isNotNull);
      expect(el.child!.mounted, isTrue);
    });

    test('child identity preserved when canUpdate=true', () {
      final el = owner.mountRoot(_SimpleP()) as StatelessElement;
      el.markNeedsHarvest();
      owner.flushHarvest();
      final first = el.child;

      el.markNeedsHarvest();
      owner.flushHarvest();
      expect(el.child, same(first));
    });

    test('child remounted when canUpdate=false (key change)', () {
      final el = owner.mountRoot(
        _SimpleP(child: const _Leaf(key: 'a')),
      ) as StatelessElement;
      el.markNeedsHarvest();
      owner.flushHarvest();
      final oldChild = el.child!;
      expect(oldChild.mounted, isTrue);

      el.update(_SimpleP(child: const _Leaf(key: 'b')));
      el.markNeedsHarvest();
      owner.flushHarvest();

      expect(el.child, isNot(same(oldChild)));
      expect(oldChild.mounted, isFalse);
      expect(el.child!.mounted, isTrue);
    });

    test('unmounts child before clearing self', () {
      final el = owner.mountRoot(_SimpleP()) as StatelessElement;
      el.markNeedsHarvest();
      owner.flushHarvest();
      final child = el.child!;

      el.unmount();

      expect(child.mounted, isFalse);
      expect(el.mounted, isFalse);
    });
  });

  group('InheritedPerception + StatelessPerception headline', () {
    late PerceptionOwner owner;

    setUp(() {
      owner = PerceptionOwner();
    });
    tearDown(() => owner.dispose());

    test('re-reads new value after provider update', () {
      final tracker = _Tracker();
      final ipEl = owner.mountRoot(
        InheritedPerception<String>(value: 'a', child: _ReadingP(tracker)),
      ) as InheritedPerceptionElement<String>;
      final statelessEl = ipEl.childElement! as StatelessElement;

      statelessEl.markNeedsHarvest();
      owner.flushHarvest();
      expect(tracker.builds, 1);
      expect(tracker.lastValue, 'a');

      ipEl.update(
        InheritedPerception<String>(value: 'b', child: _ReadingP(tracker)),
      );
      owner.flushHarvest();

      expect(tracker.builds, 2);
      expect(tracker.lastValue, 'b');
    });

    test('no rebuild when value unchanged', () {
      final tracker = _Tracker();
      final ipEl = owner.mountRoot(
        InheritedPerception<String>(value: 'a', child: _ReadingP(tracker)),
      ) as InheritedPerceptionElement<String>;
      final statelessEl = ipEl.childElement! as StatelessElement;

      statelessEl.markNeedsHarvest();
      owner.flushHarvest();
      expect(tracker.builds, 1);

      ipEl.update(
        InheritedPerception<String>(value: 'a', child: _ReadingP(tracker)),
      );
      owner.flushHarvest();

      expect(tracker.builds, 1);
    });
  });
}
