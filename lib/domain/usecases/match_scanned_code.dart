import '../entities/product.dart';

/// The backend has no exact barcode endpoint: `GET /products?search=` is a
/// LIKE over name, SKU and barcode. A scan must only ever add the product
/// whose barcode or SKU is *exactly* the scanned code (same rule as the web
/// POS), never a fuzzy name match. Barcode wins over SKU.
Product? matchScannedCode(Iterable<Product> candidates, String rawCode) {
  final code = rawCode.trim();
  if (code.isEmpty) return null;
  final active = candidates.where((p) => p.isActive);
  return active.where((p) => p.barcode == code).firstOrNull ?? active.where((p) => p.sku == code).firstOrNull;
}
