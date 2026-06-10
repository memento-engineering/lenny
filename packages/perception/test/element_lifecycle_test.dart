import 'package:perception/perception.dart';
import 'package:test/test.dart';

class _P extends Perception {
  const _P({this.tag = '', super.key});
  final String tag;
  @override
  _E createElement() => _E(this);
}

class _E extends PerceptionElement {
  _E(super.p);
  final calls = <String>[];
  @override
  void mount(PerceptionElement? parent, Object? slot) {
    super.mount(parent, slot);
    calls.add('mount');
  }

  @override
  void update(Perception p) {
    super.update(p);
    calls.add('update');
  }

  @override
  void unmount() {
    calls.add('unmount');
    super.unmount();
  }
}

void main() {
  group('PerceptionElement lifecycle', () {
    test('mount: sets mounted=true, perceptionId non-empty', () {
      final el = _E(_P());
      expect(el.mounted, isFalse);
      el.mount(null, null);
      expect(el.mounted, isTrue);
      expect(el.perceptionId, isNotEmpty);
      expect(el.calls, equals(['mount']));
    });

    test('mount: perceptionId is stable after update', () {
      final el = _E(_P())..mount(null, null);
      final id = el.perceptionId;
      el.update(_P(tag: 'x'));
      expect(el.perceptionId, equals(id));
    });

    test('mount: throws AssertionError on double-mount', () {
      final el = _E(_P())..mount(null, null);
      expect(() => el.mount(null, null), throwsA(isA<AssertionError>()));
    });

    test('unmount: sets mounted=false', () {
      final el = _E(_P())..mount(null, null);
      el.unmount();
      expect(el.mounted, isFalse);
      expect(el.calls, equals(['mount', 'unmount']));
    });

    test('unmount: throws AssertionError if already unmounted', () {
      final el = _E(_P());
      expect(() => el.unmount(), throwsA(isA<AssertionError>()));
    });

    test('update: replaces config, records call', () {
      final el = _E(_P(tag: 'a'))..mount(null, null);
      el.update(_P(tag: 'b'));
      expect((el.perception as _P).tag, equals('b'));
      expect(el.calls, equals(['mount', 'update']));
    });

    test('update: throws AssertionError if unmounted', () {
      final el = _E(_P());
      expect(() => el.update(_P()), throwsA(isA<AssertionError>()));
    });

    test(
      'update: throws AssertionError when canUpdate=false (key mismatch)',
      () {
        final el = _E(_P(key: 'a'))..mount(null, null);
        expect(() => el.update(_P(key: 'b')), throwsA(isA<AssertionError>()));
      },
    );
  });

  group('updateChild (single-child reconciliation)', () {
    late _E root;
    setUp(() => root = _E(_P())..mount(null, null));

    test('null perception: unmounts child and returns null', () {
      final child = _E(_P())..mount(root, 0);
      expect(root.updateChild(child, null, 0), isNull);
      expect(child.mounted, isFalse);
      expect(child.calls, containsAllInOrder(['mount', 'unmount']));
    });

    test('null child: mounts fresh element', () {
      final result = root.updateChild(null, _P(tag: 'new'), 0);
      expect(result, isNotNull);
      expect(result!.mounted, isTrue);
    });

    test(
      'canUpdate=true: updates in place, same object, perceptionId preserved',
      () {
        final child = _E(_P(tag: 'a'))..mount(root, 0);
        final oldId = child.perceptionId;
        final result = root.updateChild(child, _P(tag: 'b'), 0);
        expect(result, same(child));
        expect(result!.perceptionId, equals(oldId));
        expect(child.calls, equals(['mount', 'update']));
      },
    );

    test('canUpdate=false (key mismatch): unmounts old, mounts new', () {
      final child = _P(key: 'x').createElement()..mount(root, 0);
      final result = root.updateChild(child, _P(key: 'y'), 0);
      expect(result, isNot(same(child)));
      expect(child.mounted, isFalse);
      expect(result!.mounted, isTrue);
    });
  });

  group('updateChildren (multi-child keyed reconciliation)', () {
    late _E root;
    setUp(() => root = _E(_P())..mount(null, null));

    List<_E> mountAll(List<Perception> ps) {
      return ps.indexed
          .map((r) => ps[r.$1].createElement() as _E..mount(root, r.$1))
          .toList();
    }

    test('keyed reorder preserves element identity (fork #2)', () {
      final els = mountAll([
        _P(tag: 'a', key: 'k-a'),
        _P(tag: 'b', key: 'k-b'),
        _P(tag: 'c', key: 'k-c'),
      ]);
      final ids = els.map((e) => e.perceptionId).toList();

      final result = root.updateChildren(els, [
        _P(tag: 'c2', key: 'k-c'),
        _P(tag: 'a2', key: 'k-a'),
        _P(tag: 'b2', key: 'k-b'),
      ]);

      expect(result[0].perceptionId, equals(ids[2])); // c reused
      expect(result[1].perceptionId, equals(ids[0])); // a reused
      expect(result[2].perceptionId, equals(ids[1])); // b reused
      expect(result.every((e) => e.mounted), isTrue);
    });

    test('unmatched key: old unmounted, new element mounted', () {
      final els = mountAll([_P(key: 'k-a'), _P(key: 'k-b')]);
      final result = root.updateChildren(els, [_P(key: 'k-a'), _P(key: 'k-c')]);

      expect(result[0], same(els[0]));
      expect(result[1], isNot(same(els[1])));
      expect(els[1].mounted, isFalse);
      expect(result[1].mounted, isTrue);
    });

    test('shorter new list: extra old elements are unmounted', () {
      final els = mountAll([_P(key: 'k-a'), _P(key: 'k-b')]);
      final result = root.updateChildren(els, [_P(key: 'k-a')]);

      expect(result.length, equals(1));
      expect(result[0], same(els[0]));
      expect(els[1].mounted, isFalse);
    });

    test('longer new list: extra perceptions are mounted fresh', () {
      final els = mountAll([_P(key: 'k-a')]);
      final result = root.updateChildren(els, [_P(key: 'k-a'), _P(key: 'k-b')]);

      expect(result.length, equals(2));
      expect(result[0], same(els[0]));
      expect(result[1].mounted, isTrue);
    });

    test('unkeyed: elements updated positionally when types match', () {
      final els = mountAll([_P(tag: 'a'), _P(tag: 'b')]);
      final ids = els.map((e) => e.perceptionId).toList();

      final result = root.updateChildren(els, [_P(tag: 'a2'), _P(tag: 'b2')]);

      expect(result[0].perceptionId, equals(ids[0]));
      expect(result[1].perceptionId, equals(ids[1]));
    });
  });
}
