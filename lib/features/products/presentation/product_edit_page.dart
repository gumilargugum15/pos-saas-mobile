import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/rupiah_input.dart';
import '../../../data/repositories/catalog_repository_impl.dart';
import '../../../data/repositories/product_edit_repository.dart';
import '../../../domain/entities/product.dart';
import '../../auth/application/session_controller.dart';
import '../../cart/application/cart_controller.dart';
import '../application/catalog_controller.dart';
import 'product_widgets.dart';

/// Fresh product data for the edit form (includes cost price).
final productForEditProvider = FutureProvider.autoDispose.family<Product, int>(
  (ref, id) => ref.watch(catalogRepositoryProvider).product(id),
);

/// Picks a product photo. Overridable in tests.
final productPhotoPickerProvider = Provider<Future<String?> Function(ImageSource source)>((ref) {
  return (source) async {
    // Backend limit is 2 MB ("image|max:2048"): downscale on the device.
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 80);
    return file?.path;
  };
});

/// Edit a product (Admin / Owner — permission `manage-products`). Mirrors
/// the web admin product form; only changed fields are sent.
class ProductEditPage extends ConsumerWidget {
  const ProductEditPage({super.key, required this.productId});

  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(cashierCapabilitiesProvider)?.canEditProducts ?? false;
    final product = ref.watch(productForEditProvider(productId));

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Produk')),
      body: SafeArea(
        child: !allowed
            ? const StatusView(icon: Icons.lock_outline, message: 'Anda tidak memiliki akses untuk mengubah produk.')
            : product.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => StatusView(
                  icon: Icons.cloud_off,
                  message: e is AppFailure ? e.message : 'Produk tidak dapat dimuat.',
                  actionLabel: 'Coba Lagi',
                  onAction: () => ref.invalidate(productForEditProvider(productId)),
                ),
                data: (p) => _ProductForm(product: p),
              ),
      ),
    );
  }
}

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({required this.product});

  final Product product;

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product.name);
  late final _sku = TextEditingController(text: widget.product.sku);
  late final _barcode = TextEditingController(text: widget.product.barcode ?? '');
  late final _price = TextEditingController(text: _rupiah(widget.product.price));
  late final _cost = TextEditingController(text: _rupiah(widget.product.costPrice ?? const Money.zero()));
  late final _stock = TextEditingController(text: '${widget.product.stock}');
  late final _minStock = TextEditingController(text: '${widget.product.minStock}');
  late final _tax = TextEditingController(text: _percentText(widget.product.taxHundredths));
  late final _discount = TextEditingController(text: _percentText(widget.product.discountHundredths));
  late int? _categoryId = widget.product.categoryId;
  late int? _brandId = widget.product.brandId;
  late int? _unitId = widget.product.unitId;
  late bool _active = widget.product.isActive;
  String? _photoPath;
  bool _saving = false;
  AppFailure? _failure;

  static String _rupiah(Money m) => formatRupiahDigits('${m.rupiahRounded}');

  static String _percentText(int hundredths) {
    final whole = hundredths ~/ 100;
    final frac = hundredths % 100;
    if (frac == 0) return '$whole';
    return '$whole.${frac.toString().padLeft(2, '0')}'.replaceFirst(RegExp(r'0$'), '');
  }

  /// "12,5" / "12.5" → hundredths (1250); null when invalid.
  static int? _hundredths(String text) {
    final v = double.tryParse(text.trim().replaceAll(',', '.'));
    return v == null ? null : (v * 100).round();
  }

  @override
  void dispose() {
    for (final c in [_name, _sku, _barcode, _price, _cost, _stock, _minStock, _tax, _discount]) {
      c.dispose();
    }
    super.dispose();
  }

  ProductChanges _changes() {
    final p = widget.product;
    final barcode = _barcode.text.trim();
    final price = parseRupiahInput(_price.text);
    final cost = parseRupiahInput(_cost.text);
    final stock = int.tryParse(_stock.text);
    final minStock = int.tryParse(_minStock.text);
    final tax = _hundredths(_tax.text);
    final discount = _hundredths(_discount.text);
    String? changed(String now, String before) => now != before ? now : null;

    return ProductChanges(
      name: changed(_name.text.trim(), p.name),
      sku: changed(_sku.text.trim(), p.sku),
      barcode: barcode.isNotEmpty && barcode != (p.barcode ?? '') ? barcode : null,
      clearBarcode: barcode.isEmpty && (p.barcode ?? '').isNotEmpty,
      categoryId: _categoryId != p.categoryId ? _categoryId : null,
      brandId: _brandId != p.brandId ? _brandId : null,
      unitId: _unitId != p.unitId ? _unitId : null,
      priceRupiah: price != null && price != p.price.rupiahRounded ? price : null,
      costPriceRupiah: cost != null && cost != (p.costPrice ?? const Money.zero()).rupiahRounded ? cost : null,
      stock: stock != null && stock != p.stock ? stock : null,
      minStock: minStock != null && minStock != p.minStock ? minStock : null,
      taxPercent: tax != null && tax != p.taxHundredths ? _tax.text.trim().replaceAll(',', '.') : null,
      discountPercent:
          discount != null && discount != p.discountHundredths ? _discount.text.trim().replaceAll(',', '.') : null,
      isActive: _active != p.isActive ? _active : null,
      imagePath: _photoPath,
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final path = await ref.read(productPhotoPickerProvider)(source);
      if (path != null && mounted) setState(() => _photoPath = path);
    } on PlatformException {
      if (mounted) showQuickMessage(context, 'Kamera/galeri tidak dapat dibuka. Periksa izin aplikasi.', isError: true);
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final changes = _changes();
    if (changes.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final updated = await ref.read(productEditRepositoryProvider).update(widget.product.id, changes);
      // Everything showing this product picks up the new data.
      ref.read(cartControllerProvider.notifier).syncProducts([updated]);
      ref.invalidate(catalogControllerProvider);
      ref.invalidate(productForEditProvider(widget.product.id));
      if (!mounted) return;
      showQuickMessage(context, 'Produk ${updated.name} diperbarui.');
      Navigator.of(context).pop(updated);
    } on AppFailure catch (f) {
      if (mounted) setState(() => _failure = f);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Server-side field errors (unique SKU/barcode, missing category…) in
  /// Indonesian; Laravel's built-in messages are English.
  String? _serverError(String field, String label) {
    final msg = _failure?.fieldError(field);
    if (msg == null) return null;
    if (msg.contains('taken')) return '$label sudah dipakai produk lain.';
    return '$label tidak valid.';
  }

  Future<bool> _confirmDiscard() async {
    if (_changes().isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buang perubahan?'),
        content: const Text('Perubahan pada produk ini belum disimpan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Lanjut Edit')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Buang')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final brands = ref.watch(brandOptionsProvider).value ?? const <LookupItem>[];
    final units = ref.watch(unitOptionsProvider).value ?? const <LookupItem>[];
    final p = widget.product;

    // Keep the current value selectable even if it is inactive / not listed.
    List<DropdownMenuItem<int>> items(List<LookupItem> list, int? current, String? currentName) => [
          for (final i in list) DropdownMenuItem(value: i.id, child: Text(i.name)),
          if (current != null && !list.any((i) => i.id == current))
            DropdownMenuItem(value: current, child: Text(currentName ?? '#$current')),
        ];
    String? required(String? v) => (v ?? '').trim().isEmpty ? 'Wajib diisi.' : null;
    String? number(String? v, {bool percent = false}) {
      final text = (v ?? '').trim();
      if (text.isEmpty) return 'Wajib diisi.';
      final h = _hundredths(text);
      if (h == null || h < 0) return 'Angka tidak valid.';
      if (percent && h > 10000) return 'Maksimal 100.';
      return null;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.all(Radius.circular(KagoemTokens.radiusXl)),
                            child: SizedBox.square(
                              dimension: 96,
                              child: _photoPath != null
                                  ? Image.file(File(_photoPath!), fit: BoxFit.cover)
                                  : ProductImage(product: p),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                OutlinedButton.icon(
                                  key: const Key('photo-camera'),
                                  onPressed: _saving ? null : () => _pickPhoto(ImageSource.camera),
                                  icon: const Icon(Icons.photo_camera_outlined),
                                  label: const Text('Kamera'),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  key: const Key('photo-gallery'),
                                  onPressed: _saving ? null : () => _pickPhoto(ImageSource.gallery),
                                  icon: const Icon(Icons.photo_library_outlined),
                                  label: const Text('Galeri'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_failure?.fieldError('image') != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Foto tidak valid (maks. 2 MB, format gambar).',
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (_failure != null && _failure!.fieldErrors.isEmpty) ...[
                        MessageBanner(_failure!.message),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        key: const Key('edit-name'),
                        controller: _name,
                        maxLength: 255,
                        decoration: InputDecoration(labelText: 'Nama produk *', errorText: _serverError('name', 'Nama')),
                        validator: required,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: const Key('edit-sku'),
                              controller: _sku,
                              maxLength: 100,
                              decoration: InputDecoration(labelText: 'SKU *', errorText: _serverError('sku', 'SKU')),
                              validator: required,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              key: const Key('edit-barcode'),
                              controller: _barcode,
                              maxLength: 50,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Barcode',
                                errorText: _serverError('barcode', 'Barcode'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      DropdownButtonFormField<int>(
                        initialValue: _categoryId,
                        isExpanded: true,
                        items: items([for (final c in categories) LookupItem(c.id, c.name)], p.categoryId, p.categoryName),
                        decoration: InputDecoration(
                          labelText: 'Kategori *',
                          errorText: _serverError('category_id', 'Kategori'),
                        ),
                        validator: (v) => v == null ? 'Wajib dipilih.' : null,
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _brandId,
                              isExpanded: true,
                              items: items(brands, p.brandId, p.brandName),
                              decoration: InputDecoration(
                                labelText: 'Merek *',
                                errorText: _serverError('brand_id', 'Merek'),
                              ),
                              validator: (v) => v == null ? 'Wajib dipilih.' : null,
                              onChanged: (v) => setState(() => _brandId = v),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _unitId,
                              isExpanded: true,
                              items: items(units, p.unitId, p.unitName),
                              decoration: InputDecoration(
                                labelText: 'Satuan *',
                                errorText: _serverError('unit_id', 'Satuan'),
                              ),
                              validator: (v) => v == null ? 'Wajib dipilih.' : null,
                              onChanged: (v) => setState(() => _unitId = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: const Key('edit-price'),
                              controller: _price,
                              keyboardType: TextInputType.number,
                              inputFormatters: const [RupiahInputFormatter()],
                              decoration: const InputDecoration(labelText: 'Harga jual *', prefixText: 'Rp '),
                              validator: (v) => parseRupiahInput(v ?? '') == null ? 'Wajib diisi.' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              key: const Key('edit-cost'),
                              controller: _cost,
                              keyboardType: TextInputType.number,
                              inputFormatters: const [RupiahInputFormatter()],
                              decoration: const InputDecoration(labelText: 'Harga modal *', prefixText: 'Rp '),
                              validator: (v) => parseRupiahInput(v ?? '') == null ? 'Wajib diisi.' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: const Key('edit-stock'),
                              controller: _stock,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(labelText: 'Stok'),
                              validator: (v) => int.tryParse(v ?? '') == null ? 'Wajib diisi.' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _minStock,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(labelText: 'Stok minimum'),
                              validator: (v) => int.tryParse(v ?? '') == null ? 'Wajib diisi.' : null,
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
                        child: Text(
                          'Stok diubah langsung, seperti di web admin (tanpa catatan mutasi stok).',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: const Key('edit-tax'),
                              controller: _tax,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Pajak', suffixText: '%'),
                              validator: (v) => number(v, percent: true),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              key: const Key('edit-discount'),
                              controller: _discount,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Diskon', suffixText: '%'),
                              validator: (v) => number(v, percent: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        key: const Key('edit-active'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Produk aktif'),
                        subtitle: const Text('Produk nonaktif tidak muncul di kasir.'),
                        value: _active,
                        onChanged: (v) => setState(() => _active = v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton(
                  key: const Key('edit-save'),
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  child: Text(_saving ? 'Menyimpan...' : 'SIMPAN'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
