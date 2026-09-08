library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_perception/genesis_perception.dart';
import 'package:leonard_flutter/contract.dart';
import 'package:leonard_router/leonard_router.dart';

class _FakeRouterExtension extends RouterExtension {
  _FakeRouterExtension(this.snapshot)
    : super(navigatorKey: GlobalKey<NavigatorState>());

  final RouteSnapshot? snapshot;

  @override
  RouteSnapshot? readSnapshot() => snapshot;
}

Map<String, Object?> _harvest(RouteSnapshot? snapshot) {
  final PerceptionOwner owner = PerceptionOwner();
  try {
    final Branch root = owner.mountRoot(
      RouterPerception(RouteSnapshotAnchor(_FakeRouterExtension(snapshot))),
    );
    return serializePerceptionFragment(root);
  } finally {
    owner.dispose();
  }
}

void main() {
  test('snapshot becomes the exact router perception shape', () {
    const RouteSnapshot snapshot = RouteSnapshot(
      currentRouteName: '/checkout/payment',
      stack: <String>['/', '/checkout', '/checkout/payment'],
      arguments: <String, Object?>{'cart_id': 42},
    );

    expect(_harvest(snapshot), <String, Object?>{
      'current_route_name': '/checkout/payment',
      'stack': <String>['/', '/checkout', '/checkout/payment'],
      'arguments': <String, Object?>{'cart_id': 42},
    });
  });

  test('missing snapshot becomes the defensive empty router shape', () {
    expect(_harvest(null), <String, Object?>{
      'current_route_name': null,
      'stack': <String>[],
      'arguments': null,
    });
  });
}
