import 'package:perception/perception.dart';
import 'package:test/test.dart';

class _P extends Perception {
  const _P({this.tag = ''});
  final String tag;
  @override
  _E createElement() => _E(this);
}

class _E extends PerceptionElement {
  _E(_P super.perception);
  bool harvested = false;
  @override
  void markNeedsHarvest() {
    harvested = true;
    super.markNeedsHarvest();
  }
}

InheritedPerceptionElement<String> _mountInherited(
  PerceptionElement parent,
  String value,
) {
  final ip = InheritedPerception<String>(value: value, child: _P());
  final el = ip.createElement();
  el.mount(parent, 0);
  return el;
}

void main() {
  group('InheritedPerception construction', () {
    test('createElement returns InheritedPerceptionElement<T>', () {
      final ip = InheritedPerception<String>(value: 'x', child: _P());
      expect(ip.createElement(), isA<InheritedPerceptionElement<String>>());
    });

    test('value and child are preserved', () {
      final child = _P(tag: 'c');
      final ip = InheritedPerception<int>(value: 42, child: child);
      expect(ip.value, 42);
      expect(ip.child, same(child));
    });
  });

  group('dependOnInheritedPerceptionOfExactType — lookup', () {
    late PerceptionOwner testOwner;
    late _E root;
    setUp(() {
      testOwner = PerceptionOwner();
      root = testOwner.mountRoot(_P()) as _E;
    });
    tearDown(() => testOwner.dispose());

    test('returns value from direct parent provider', () {
      final ip = _mountInherited(root, 'hello');
      final leaf = _E(_P())..mount(ip, 0);

      expect(leaf.dependOnInheritedPerceptionOfExactType<String>(), 'hello');
    });

    test('returns value from grandparent provider (O(n) walk)', () {
      final ip = _mountInherited(root, 'deep');
      final mid = _E(_P())..mount(ip, 0);
      final leaf = _E(_P())..mount(mid, 0);

      expect(leaf.dependOnInheritedPerceptionOfExactType<String>(), 'deep');
    });

    test('returns null when no ancestor of type T exists', () {
      final leaf = _E(_P())..mount(root, 0);
      expect(leaf.dependOnInheritedPerceptionOfExactType<String>(), isNull);
    });

    test('skips InheritedPerception<OtherType> and finds correct type', () {
      final intIp = InheritedPerception<int>(value: 7, child: _P());
      final intEl = intIp.createElement();
      intEl.mount(root, 0);

      final strIp = InheritedPerception<String>(value: 'found', child: _P());
      final strEl = strIp.createElement();
      strEl.mount(intEl, 0);

      final leaf = _E(_P())..mount(strEl, 0);
      expect(leaf.dependOnInheritedPerceptionOfExactType<String>(), 'found');
      expect(leaf.dependOnInheritedPerceptionOfExactType<int>(), 7);
    });
  });

  group('dependency registration', () {
    late PerceptionOwner testOwner;
    late _E root;
    late InheritedPerceptionElement<String> ip;
    late _E leaf;

    setUp(() {
      testOwner = PerceptionOwner();
      root = testOwner.mountRoot(_P()) as _E;
      ip = _mountInherited(root, 'v');
      leaf = _E(_P())..mount(ip, 0);
    });
    tearDown(() => testOwner.dispose());

    test('lookup registers the caller as a dependent', () {
      leaf.dependOnInheritedPerceptionOfExactType<String>();
      expect(ip.dependents, contains(leaf));
    });

    test('registration is idempotent — two calls, one entry', () {
      leaf.dependOnInheritedPerceptionOfExactType<String>();
      leaf.dependOnInheritedPerceptionOfExactType<String>();
      expect(ip.dependents.length, 1);
    });

    test('leaf._dependencies contains the provider', () {
      leaf.dependOnInheritedPerceptionOfExactType<String>();
      expect(leaf.dependencies, contains(ip));
    });
  });

  group('invalidation', () {
    late PerceptionOwner testOwner;
    late _E root;
    late InheritedPerceptionElement<String> ip;
    late _E leaf;

    setUp(() {
      testOwner = PerceptionOwner();
      root = testOwner.mountRoot(_P()) as _E;
      ip = _mountInherited(root, 'old');
      leaf = _E(_P())..mount(ip, 0);
      leaf.dependOnInheritedPerceptionOfExactType<String>();
    });
    tearDown(() => testOwner.dispose());

    test(
      'value change (updateShouldNotify=true) marks dependent needsHarvest',
      () {
        expect(leaf.harvested, isFalse);
        ip.update(InheritedPerception<String>(value: 'new', child: _P()));
        expect(leaf.harvested, isTrue);
      },
    );

    test(
      'equal value (updateShouldNotify=false) does NOT mark needsHarvest',
      () {
        ip.update(InheritedPerception<String>(value: 'old', child: _P()));
        expect(leaf.harvested, isFalse);
      },
    );

    test('custom updateShouldNotify is honoured', () {
      const nn = _NeverNotify('a');
      final nnEl = nn.createElement();
      nnEl.mount(root, 1);
      final l2 = _E(_P())..mount(nnEl, 0);
      l2.dependOnInheritedPerceptionOfExactType<String>();

      nnEl.update(const _NeverNotify('b'));
      expect(l2.harvested, isFalse);
    });
  });

  group('dependent unmount cleanup', () {
    late PerceptionOwner testOwner;
    late _E root;
    late InheritedPerceptionElement<String> ip;
    late _E leaf;

    setUp(() {
      testOwner = PerceptionOwner();
      root = testOwner.mountRoot(_P()) as _E;
      ip = _mountInherited(root, 'v');
      leaf = _E(_P())..mount(ip, 0);
      leaf.dependOnInheritedPerceptionOfExactType<String>();
    });
    tearDown(() => testOwner.dispose());

    test('leaf unmount removes it from provider dependents (no leak)', () {
      expect(ip.dependents, contains(leaf));
      leaf.unmount();
      expect(ip.dependents, isNot(contains(leaf)));
    });

    test('leaf unmount clears its own _dependencies (no leak)', () {
      expect(leaf.dependencies, contains(ip));
      leaf.unmount();
      expect(leaf.dependencies, isEmpty);
    });
  });

  group('InheritedPerceptionElement unmount cleanup', () {
    late PerceptionOwner testOwner;
    late _E root;
    late InheritedPerceptionElement<String> ip;
    late _E leaf;

    setUp(() {
      testOwner = PerceptionOwner();
      root = testOwner.mountRoot(_P()) as _E;
      ip = _mountInherited(root, 'v');
      leaf = _E(_P())..mount(ip, 0);
      leaf.dependOnInheritedPerceptionOfExactType<String>();
    });
    tearDown(() => testOwner.dispose());

    test(
      'provider unmount removes itself from dependent _dependencies (no leak)',
      () {
        expect(leaf.dependencies, contains(ip));
        ip.unmount();
        expect(leaf.dependencies, isNot(contains(ip)));
      },
    );

    test('provider unmount clears its own _dependents (no leak)', () {
      expect(ip.dependents, contains(leaf));
      ip.unmount();
      expect(ip.dependents, isEmpty);
    });
  });

  group('Pure-Dart guard', () {
    test('InheritedPerceptionElement is a PerceptionElement', () {
      final ip = InheritedPerception<String>(value: 'x', child: _P());
      final el = ip.createElement();
      expect(el, isA<PerceptionElement>());
    });
  });
}

class _NeverNotify extends InheritedPerception<String> {
  const _NeverNotify(String v) : super(value: v, child: const _P());
  @override
  bool updateShouldNotify(_) => false;
}
