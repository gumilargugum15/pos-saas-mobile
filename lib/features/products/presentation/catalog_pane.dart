import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/feedback.dart';
import '../../../domain/entities/product.dart';
import '../../cart/application/cart_controller.dart';
import '../application/catalog_controller.dart';
import 'product_widgets.dart';

/// Search + category chips + infinite product grid.
///
/// Pressing Enter in the search field (what hardware barcode scanners do)
/// runs [onSubmitCode] for an exact barcode/SKU lookup.
class CatalogPane extends ConsumerStatefulWidget {
  const CatalogPane({
    super.key,
    required this.onProductTap,
    this.onProductLongPress,
    this.onSubmitCode,
    this.onScanPressed,
    this.autofocusSearch = false,
  });

  final void Function(Product product) onProductTap;
  final void Function(Product product)? onProductLongPress;

  /// Returns true when the code was consumed (field is then cleared).
  final Future<bool> Function(String code)? onSubmitCode;
  final VoidCallback? onScanPressed;
  final bool autofocusSearch;

  @override
  ConsumerState<CatalogPane> createState() => _CatalogPaneState();
}

class _CatalogPaneState extends ConsumerState<CatalogPane> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Keep the field in sync when the controller already has a query.
    _search.text = ref.read(catalogControllerProvider).search;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 600) {
      ref.read(catalogControllerProvider.notifier).loadMore();
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(catalogControllerProvider.notifier).setSearch(value);
    });
  }

  Future<void> _onSubmitted(String value) async {
    _debounce?.cancel();
    final submit = widget.onSubmitCode;
    if (submit != null && value.trim().isNotEmpty && await submit(value)) {
      _search.clear();
      ref.read(catalogControllerProvider.notifier).setSearch('');
    } else {
      ref.read(catalogControllerProvider.notifier).setSearch(value);
    }
    // Ready for the next scan.
    if (mounted) _searchFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(catalogControllerProvider);
    final cart = ref.watch(cartControllerProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('catalog-search'),
                  controller: _search,
                  focusNode: _searchFocus,
                  autofocus: widget.autofocusSearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Cari nama, SKU, atau barcode',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: ValueListenableBuilder(
                      valueListenable: _search,
                      builder: (_, value, _) => value.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              tooltip: 'Hapus pencarian',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _search.clear();
                                ref.read(catalogControllerProvider.notifier).setSearch('');
                              },
                            ),
                    ),
                  ),
                  onChanged: _onChanged,
                  onSubmitted: _onSubmitted,
                ),
              ),
              if (widget.onScanPressed != null) ...[
                const SizedBox(width: 8),
                SizedBox.square(
                  dimension: 56,
                  child: IconButton.filled(
                    key: const Key('catalog-scan'),
                    tooltip: 'Scan barcode',
                    onPressed: widget.onScanPressed,
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                ),
              ],
            ],
          ),
        ),
        const _CategoryChips(),
        Expanded(child: _buildGrid(state, cart.qtyOf)),
      ],
    );
  }

  Widget _buildGrid(CatalogState state, int Function(int productId) qtyOf) {
    final controller = ref.read(catalogControllerProvider.notifier);

    if (state.isLoading) return const Center(child: CircularProgressIndicator());
    if (state.failure != null && state.items.isEmpty) {
      return StatusView(
        icon: Icons.cloud_off,
        message: state.failure!.message,
        actionLabel: 'Coba Lagi',
        onAction: controller.refresh,
      );
    }
    if (state.isEmpty) {
      return StatusView(
        icon: Icons.inventory_2_outlined,
        message: state.search.isEmpty ? 'Belum ada produk aktif.' : 'Produk "${state.search}" tidak ditemukan.',
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                mainAxisExtent: 230,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: state.items.length,
              itemBuilder: (context, i) {
                final product = state.items[i];
                return ProductTile(
                  key: ValueKey(product.id),
                  product: product,
                  qtyInCart: qtyOf(product.id),
                  onTap: () => widget.onProductTap(product),
                  onLongPress: widget.onProductLongPress == null ? null : () => widget.onProductLongPress!(product),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Center(
                child: state.isLoadingMore
                    ? const CircularProgressIndicator()
                    : state.failure != null
                        ? TextButton.icon(
                            onPressed: controller.retryMore,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Gagal memuat. Coba lagi'),
                          )
                        : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChips extends ConsumerWidget {
  const _CategoryChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    if (categories.isEmpty) return const SizedBox.shrink();
    final selected = ref.watch(catalogControllerProvider.select((s) => s.categoryId));
    final controller = ref.read(catalogControllerProvider.notifier);

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('Semua'),
              selected: selected == null,
              onSelected: (_) => controller.setCategory(null),
            ),
          ),
          for (final c in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c.name),
                selected: selected == c.id,
                onSelected: (_) => controller.setCategory(selected == c.id ? null : c.id),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shows the outcome of an add-to-cart action.
void showCartResult(BuildContext context, CartResult result, Product product) {
  if (result.isLimited) {
    showQuickMessage(context, result.message!, isError: true);
  }
}
