import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the auth token (or null when logged out). Exposed as a
/// `StateNotifier<String?>` rather than a plain `StateProvider` so the
/// Riverpod observer surfaces transition events with stable IDs.
class AuthNotifier extends StateNotifier<String?> {
  AuthNotifier() : super(null);

  void setToken(String token) => state = token;
  void clear() => state = null;
}

final authProvider = StateNotifierProvider<AuthNotifier, String?>(
  (ref) => AuthNotifier(),
  name: 'auth',
);
