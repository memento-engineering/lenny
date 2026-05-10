import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api.dart';

final itemsProvider = FutureProvider<List<Item>>(
  (ref) => ref.watch(apiProvider).getItems(),
  name: 'items',
);
