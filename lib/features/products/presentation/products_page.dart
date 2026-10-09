import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/application/session_controller.dart';
import 'catalog_pane.dart';
import 'product_widgets.dart';

/// Product lookup (price, stock) outside of a transaction. Admin / Owner
/// (manage-products) can also add products here.
class ProductsPage extends ConsumerWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(cashierCapabilitiesProvider)?.canEditProducts ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Produk')),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              key: const Key('product-add'),
              onPressed: () => context.push('/products/new'),
              icon: const Icon(Icons.add),
              label: const Text('Tambah Produk'),
            )
          : null,
      body: SafeArea(
        child: CatalogPane(onProductTap: (p) => showProductDetail(context, p)),
      ),
    );
  }
}
