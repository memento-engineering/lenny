library;

import 'package:genesis_perception/genesis_perception.dart';

import 'dio_tracking_interceptor.dart';
import 'tracked_request.dart';

class DioPerception extends StatelessPerception {
  const DioPerception(this._interceptor, this._clock);

  final DioTrackingInterceptor _interceptor;
  final DateTime Function() _clock;

  @override
  Seed build(PerceptionContext ctx) {
    final DateTime now = _clock();
    final List<TrackedRequest> inFlight =
        _interceptor.inFlight.values.toList();
    final List<CompletedRequest> recent = _interceptor.recentCompleted;
    return Node('dio', children: <Seed>[
      Field('in_flight', <Map<String, Object?>>[
        for (final TrackedRequest t in inFlight)
          <String, Object?>{
            'id': t.id,
            'method': t.method,
            'host': t.host,
            'path': t.path,
            'elapsed_ms': t.elapsedMs(now),
            'est_remaining_ms': _estRemaining(t.elapsedMs(now)),
          },
      ]),
      Field('recent_completed', <Map<String, Object?>>[
        for (final CompletedRequest c in recent) c.toJson(),
      ]),
    ]);
  }

  static int _estRemaining(int elapsedMs) =>
      elapsedMs >= 600 ? 100 : 600 - elapsedMs;
}
