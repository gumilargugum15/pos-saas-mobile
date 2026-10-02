import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../domain/entities/product.dart';
import '../../cart/application/cart_controller.dart';
import '../../products/application/catalog_controller.dart';

enum ScanStatus { added, limited, notFound, failed }

class ScanOutcome {
  const ScanOutcome(this.status, this.message, {this.product});

  final ScanStatus status;
  final String message;
  final Product? product;

  bool get isSuccess => status == ScanStatus.added;
}

/// Scan → find product (exact barcode/SKU) → add to cart, or report
/// "not found". Never creates products. Shared by the camera scanner and
/// hardware (keyboard-wedge) scanners typing into the search field.
Future<ScanOutcome> scanToCart(Ref ref, String code) async {
  final term = code.trim();
  if (term.isEmpty) return const ScanOutcome(ScanStatus.notFound, 'Kode kosong.');

  final Product? product;
  try {
    product = await ref.read(productLookupProvider)(term);
  } on AppFailure catch (failure) {
    return ScanOutcome(ScanStatus.failed, failure.message);
  }

  if (product == null) {
    return ScanOutcome(ScanStatus.notFound, 'Produk dengan kode "$term" tidak ditemukan.');
  }

  final result = ref.read(cartControllerProvider.notifier).add(product);
  if (result.isLimited) {
    return ScanOutcome(ScanStatus.limited, result.message!, product: product);
  }
  final qty = ref.read(cartControllerProvider).qtyOf(product.id);
  return ScanOutcome(ScanStatus.added, '${product.name} ditambahkan (×$qty)', product: product);
}

/// Exposes [scanToCart] to widgets.
final scanToCartProvider = Provider<Future<ScanOutcome> Function(String code)>((ref) {
  return (code) => scanToCart(ref, code);
});
