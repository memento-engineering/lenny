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
  _ReadingP(this.tracker);
  final _Tracker tracker;
  @override
  Perception build(PerceptionContext ctx) {
    tracker.builds++;
    tracker.lastValue = ctx.dependOnInheritedPerceptionOfExactType<String>();
    return const _Leaf();
  }
}

class _SimpleP extends StatelessPerception {
  const _SimpleP({this.child = const _Leaf()});
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

    test('builds its child synchronously on mount (no external dirty)', () {
      // mountRoot alone must produce the subtree — Flutter's _firstBuild.
      // No markNeedsHarvest / flushHarvest required.
      final el = owner.mountRoot(_SimpleP()) as StatelessElement;
      expect(el.child, isNotNull);
      expect(el.child!.mounted, isTrue);
    });

    test('child identity preserved across a rebuild when canUpdate=true', () {
      final el = owner.mountRoot(_SimpleP()) as StatelessElement;
      final first = el.child;

      el.markNeedsHarvest();
      owner.flushHarvest();
      expect(el.child, same(first));
    });

    test('child remounted when canUpdate=false (key change)', () {
      final el =
          owner.mountRoot(_SimpleP(child: const _Leaf(key: 'a')))
              as StatelessElement;
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

    test('reads provider on mount, re-reads after provider update', () {
      final tracker = _Tracker();
      final ipEl =
          owner.mountRoot(
                InheritedPerception<String>(
                  value: 'a',
                  child: _ReadingP(tracker),
                ),
              )
              as InheritedPerceptionElement<String>;

      // Mounting drove the first build through the whole subtree — the
      // dependency on the provider is registered and 'a' was read.
      expect(tracker.builds, 1);
      expect(tracker.lastValue, 'a');

      ipEl.update(
        InheritedPerception<String>(value: 'b', child: _ReadingP(tracker)),
      );
      owner.flushHarvest();

      expect(tracker.builds, 2);
      expect(tracker.lastValue, 'b');
    });

    test('no rebuild when provider value unchanged', () {
      final tracker = _Tracker();
      final ipEl =
          owner.mountRoot(
                InheritedPerception<String>(
                  value: 'a',
                  child: _ReadingP(tracker),
                ),
              )
              as InheritedPerceptionElement<String>;

      expect(tracker.builds, 1);

      ipEl.update(
        InheritedPerception<String>(value: 'a', child: _ReadingP(tracker)),
      );
      owner.flushHarvest();

      expect(tracker.builds, 1);
    });
  });
}
