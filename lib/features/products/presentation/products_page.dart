import 'package:flutter/material.dart';

import 'catalog_pane.dart';
import 'product_widgets.dart';

/// Read-only product lookup (price, stock) outside of a transaction.
class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Produk')),
      body: SafeArea(
        child: CatalogPane(onProductTap: (p) => showProductDetail(context, p)),
      ),
    );
  }
}
