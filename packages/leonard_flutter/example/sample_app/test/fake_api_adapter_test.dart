import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sample_app/services/fake_api_adapter.dart';

Dio _dio() {
  final dio = Dio(BaseOptions(baseUrl: 'https://fake.local'));
  dio.httpClientAdapter = FakeApiAdapter(latency: Duration.zero);
  return dio;
}

void main() {
  group('FakeApiAdapter', () {
    test(
      'POST /auth/login with good credentials returns 200 + token',
      () async {
        final dio = _dio();
        final r = await dio.post<Map<String, Object?>>(
          '/auth/login',
          data: <String, String>{
            'email': 'demo@example.com',
            'password': 'password',
          },
        );
        expect(r.statusCode, 200);
        expect(r.data, isA<Map<String, Object?>>());
        expect(r.data!['token'], 'fake-token');
        final user = r.data!['user'] as Map<String, Object?>;
        expect(user['name'], 'Demo');
      },
    );

    test('POST /auth/login with bad credentials returns 401', () async {
      final dio = _dio();
      try {
        await dio.post<Map<String, Object?>>(
          '/auth/login',
          data: <String, String>{
            'email': 'wrong@example.com',
            'password': 'nope',
          },
        );
        fail('expected DioException for 401');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 401);
        final data = e.response?.data as Map<String, Object?>;
        expect(data['error'], 'invalid_credentials');
      }
    });

    test('GET /profile returns the demo user', () async {
      final dio = _dio();
      final r = await dio.get<Map<String, Object?>>('/profile');
      expect(r.statusCode, 200);
      expect(r.data!['email'], 'demo@example.com');
    });

    test('GET /items returns 12 items', () async {
      final dio = _dio();
      final r = await dio.get<Map<String, Object?>>('/items');
      expect(r.statusCode, 200);
      final items = r.data!['items'] as List<Object?>;
      expect(items.length, 12);
    });

    test('unknown path returns 404', () async {
      final dio = _dio();
      try {
        await dio.get<Map<String, Object?>>('/does/not/exist');
        fail('expected DioException for 404');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 404);
      }
    });

    test('latency parameter is honored', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://fake.local'));
      dio.httpClientAdapter = FakeApiAdapter(
        latency: const Duration(milliseconds: 50),
      );
      final sw = Stopwatch()..start();
      await dio.get<Map<String, Object?>>('/profile');
      sw.stop();
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(40));
    });
  });
}
