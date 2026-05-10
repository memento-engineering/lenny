import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api.dart';

final profileProvider = FutureProvider<Profile>(
  (ref) => ref.watch(apiProvider).getProfile(),
  name: 'profile',
);
