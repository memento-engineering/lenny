import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_api_adapter.dart';

/// Builds a [Dio] instance whose HTTP traffic is fully intercepted by
/// [FakeApiAdapter]. No real network is opened.
Dio buildDio() {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://fake.local',
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ),
  );
  dio.httpClientAdapter = FakeApiAdapter();
  return dio;
}

final dioProvider = Provider<Dio>((ref) => buildDio(), name: 'dio');

final apiProvider = Provider<Api>(
  (ref) => Api(ref.watch(dioProvider)),
  name: 'api',
);

/// Thin wrapper around [Dio] for the sample app's endpoints.
class Api {
  Api(this._dio);

  final Dio _dio;

  Future<String> login(String email, String password) async {
    final r = await _dio.post<Map<String, Object?>>(
      '/auth/login',
      data: <String, String>{'email': email, 'password': password},
    );
    return (r.data!)['token'] as String;
  }

  Future<Profile> getProfile() async {
    final r = await _dio.get<Map<String, Object?>>('/profile');
    final data = r.data!;
    return Profile(
      id: data['id'] as String,
      name: data['name'] as String,
      email: data['email'] as String,
    );
  }

  Future<void> updateProfile({required String name}) async {
    await _dio.put<Map<String, Object?>>(
      '/profile',
      data: <String, String>{'name': name},
    );
  }

  Future<List<Item>> getItems() async {
    final r = await _dio.get<Map<String, Object?>>('/items');
    final list = (r.data!['items'] as List<Object?>)
        .cast<Map<String, Object?>>();
    return [
      for (final m in list)
        Item(id: m['id'] as String, title: m['title'] as String),
    ];
  }

  /// Gauntlet: confirmation code revealed only after a slow round-trip.
  Future<String> fetchConfirmationCode() async {
    final r = await _dio.get<Map<String, Object?>>('/confirmation');
    return r.data!['code'] as String;
  }

  /// Gauntlet: the server always reconciles a "like" back to false, so the
  /// optimistic UI flash disagrees with the settled state.
  Future<bool> toggleLike() async {
    final r = await _dio.post<Map<String, Object?>>('/like');
    return r.data!['liked'] as bool;
  }

  /// Gauntlet: debounced search. Returns the result titles for [query].
  Future<List<String>> search(String query) async {
    final r = await _dio.get<Map<String, Object?>>(
      '/search',
      queryParameters: <String, Object?>{'q': query},
    );
    final list = (r.data!['results'] as List<Object?>)
        .cast<Map<String, Object?>>();
    return <String>[for (final m in list) m['title'] as String];
  }

  Future<void> updateSettings({
    required String theme,
    required bool notifications,
    required String language,
  }) async {
    await _dio.put<Map<String, Object?>>(
      '/settings',
      data: <String, Object?>{
        'theme': theme,
        'notifications': notifications,
        'language': language,
      },
    );
  }
}

class Profile {
  const Profile({required this.id, required this.name, required this.email});
  final String id;
  final String name;
  final String email;
}

class Item {
  const Item({required this.id, required this.title});
  final String id;
  final String title;
}
