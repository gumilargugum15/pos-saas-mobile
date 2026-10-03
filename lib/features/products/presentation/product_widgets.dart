import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/media_url.dart';
import '../../../domain/entities/product.dart';
import '../../settings/settings_providers.dart';

class ProductImage extends ConsumerWidget {
  const ProductImage({super.key, required this.product, this.size});

  final Product product;
  final double? size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Text(
        product.name.isEmpty ? '?' : product.name.characters.first.toUpperCase(),
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant),
      ),
    );
    final url = MediaUrl.resolve(product.imageUrl, ref.watch(appConfigProvider).apiBaseUrl);
    final child = url == null
        ? placeholder
        : Image.network(
            url,
            fit: BoxFit.cover,
            cacheWidth: 300,
            errorBuilder: (_, _, _) => placeholder,
            loadingBuilder: (_, image, progress) => progress == null ? image : placeholder,
          );
    return SizedBox(width: size, height: size, child: child);
  }
}

class StockBadge extends StatelessWidget {
  const StockBadge({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = product.isOutOfStock
        ? ('Habis', scheme.error)
        : product.isLowStock
            ? ('Stok ${product.stock}', BrandColors.warning)
            : ('Stok ${product.stock}', scheme.onSurfaceVariant);
    return Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12));
  }
}

/// Grid tile in the POS catalog. Tap adds to cart; long press shows details.
class ProductTile extends ConsumerWidget {
  const ProductTile({super.key, required this.product, this.qtyInCart = 0, this.onTap, this.onLongPress});

  final Product product;
  final int qtyInCart;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final disabled = product.isOutOfStock;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: qtyInCart > 0 ? scheme.primary : scheme.outlineVariant, width: qtyInCart > 0 ? 2 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ProductImage(product: product),
                    if (product.hasDiscount)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: _Pill('-${formatPercent(product.discountHundredths)}', scheme.error, scheme.onError),
                      ),
                    if (qtyInCart > 0)
                      Positioned(right: 6, top: 6, child: _Pill('×$qtyInCart', scheme.primary, scheme.onPrimary)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      ref.money(product.price),
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: scheme.primary),
                    ),
                    StockBadge(product: product),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.background, this.foreground);

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: foreground, fontWeight: FontWeight.w700, fontSize: 12)),
      );
}

/// Product details as a bottom sheet. [onAdd] is null outside the POS.
Future<void> showProductDetail(BuildContext context, Product product, {VoidCallback? onAdd}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ProductDetail(product: product, onAdd: onAdd),
  );
}

class _ProductDetail extends ConsumerWidget {
  const _ProductDetail({required this.product, this.onAdd});

  final Product product;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(width: 120, child: Text(label, style: textTheme.bodyMedium)),
              Expanded(child: Text(value, style: textTheme.titleSmall)),
            ],
          ),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(aspectRatio: 16 / 9, child: ProductImage(product: product)),
            ),
            const SizedBox(height: 16),
            Text(product.name, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(ref.money(product.price), style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const Divider(height: 24),
            row('SKU', product.sku),
            row('Barcode', product.barcode ?? '-'),
            row('Kategori', product.categoryName ?? '-'),
            row('Satuan', product.unitName ?? '-'),
            row('Stok', product.isOutOfStock ? 'Habis' : '${product.stock}'),
            if (product.hasDiscount) row('Diskon', formatPercent(product.discountHundredths)),
            row('Pajak', formatPercent(product.taxHundredths)),
            if (onAdd != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: product.isOutOfStock
                    ? null
                    : () {
                        Navigator.pop(context);
                        onAdd!();
                      },
                icon: const Icon(Icons.add_shopping_cart),
                label: Text(product.isOutOfStock ? 'Stok habis' : 'Tambah ke keranjang'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
