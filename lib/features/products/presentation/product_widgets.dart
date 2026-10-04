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
    // Web: "bg-muted" with a package icon when there is no image.
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(child: Icon(Icons.inventory_2_outlined, color: scheme.onSurfaceVariant, size: 26)),
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

/// Web stock pill: "{n} stok" on a 10% tint of success / warning / danger.
class StockBadge extends StatelessWidget {
  const StockBadge({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = product.isOutOfStock
        ? ('Habis', scheme.error)
        : product.isLowStock
            ? ('${product.stock} stok', BrandColors.warning)
            : ('${product.stock} stok', BrandColors.success);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }
}

/// Catalog card, as in the web POS: "rounded-2xl bg-card border p-3
/// shadow-soft", image area "rounded-xl bg-muted", SKU, name, primary
/// price and stock pill. Tap adds to cart; long press shows details.
class ProductTile extends ConsumerWidget {
  const ProductTile({super.key, required this.product, this.qtyInCart = 0, this.onTap, this.onLongPress});

  final Product product;
  final int qtyInCart;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final selected = qtyInCart > 0;
    const radius = BorderRadius.all(Radius.circular(KagoemTokens.radius2xl));

    return Opacity(
      opacity: product.isOutOfStock ? 0.5 : 1,
      child: Material(
        color: Theme.of(context).cardTheme.color,
        elevation: 1,
        shadowColor: scheme.shadow.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(KagoemTokens.radiusXl)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ProductImage(product: product),
                        if (product.hasDiscount)
                          Positioned(
                            left: 6,
                            top: 6,
                            child: _Badge('-${formatPercent(product.discountHundredths)}', scheme.error, scheme.onError),
                          ),
                        if (selected)
                          Positioned(right: 6, top: 6, child: _Badge('×$qtyInCart', scheme.primary, scheme.onPrimary)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  product.sku,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: scheme.onSurfaceVariant),
                ),
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.25),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          ref.money(product.price),
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: scheme.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    StockBadge(product: product),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.background, this.foreground);

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
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
