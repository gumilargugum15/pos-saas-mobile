import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/sales_repository_impl.dart';
import '../../domain/entities/party.dart';

/// Active customers matching a search term (first page, 20 results).
final customerSearchProvider = FutureProvider.autoDispose.family<List<Customer>, String>((ref, search) async {
  final page = await ref.watch(salesRepositoryProvider).customers(search: search);
  return page.items;
});
