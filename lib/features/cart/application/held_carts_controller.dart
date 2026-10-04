import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/app_failure.dart';
import '../../../data/repositories/catalog_repository_impl.dart';
import '../../../data/repositories/held_cart_repository.dart';
import '../../../domain/entities/held_cart.dart';
import '../../../domain/entities/product.dart';
import '../../auth/application/session_controller.dart';
import '../../checkout/application/checkout_controller.dart';
import '../../receipt/receipt_providers.dart';
import '../../settings/settings_providers.dart';
import 'cart_controller.dart';

/// A reason a hold/resume cannot happen, safe to show to the cashier.
class HoldException implements Exception {
  const HoldException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What changed when a held cart was brought back.
class ResumeReport {
  const ResumeReport(this.notes);

  /// e.g. "Harga Kopi berubah: Rp 10.000 → Rp 12.000".
  final List<String> notes;

  bool get hasChanges => notes.isNotEmpty;
}

/// Hold ("tahan") the current cart to serve the next customer, and resume
/// it later — the web POS "Hold / Resume", with these safeguards:
///
/// - stored per tenant and cashier on the device, surviving app restarts;
/// - resuming while the cart has items holds the current cart first, so
///   nothing is lost;
/// - prices, availability and stock are re-read from the server on resume
///   (the backend charges current prices anyway); changes are reported.
class HeldCartsController extends AsyncNotifier<List<HeldCart>> {
  static const _uuid = Uuid();
  HeldCartRepository? _repo;

  @override
  Future<List<HeldCart>> build() async {
    final tenant = ref.watch(activeTenantProvider);
    final user = ref.watch(currentUserProvider);
    if (tenant == null || user == null) {
      _repo = null;
      return const [];
    }
    _repo = HeldCartRepository(ref.watch(deviceStoreProvider), tenantId: tenant.id, userId: user.id);
    return _repo!.load();
  }

  /// Parks the current cart and customer, then clears them for the next
  /// customer. Saved to the device before anything is cleared.
  Future<HeldCart> hold({String? note}) async {
    final repo = _repo;
    if (repo == null) throw const HoldException('Sesi belum siap.');
    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty) throw const HoldException('Keranjang masih kosong.');
    final checkout = ref.read(checkoutControllerProvider);
    if (checkout.phase != CheckoutPhase.editing) {
      throw const HoldException('Selesaikan pembayaran yang sedang diproses terlebih dahulu.');
    }

    final current = await future;
    if (current.length >= HeldCartRepository.maxHeld) {
      throw const HoldException(
        'Maksimal ${HeldCartRepository.maxHeld} transaksi ditahan. Lanjutkan atau hapus salah satu.',
      );
    }

    final trimmed = note?.trim();
    final held = HeldCart(
      id: _uuid.v4(),
      lines: cart.lines,
      createdAt: DateTime.now(),
      customer: checkout.customer,
      note: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
    final next = [held, ...current];
    await repo.save(next);
    state = AsyncData(next);

    ref.read(cartControllerProvider.notifier).clear();
    ref.read(checkoutControllerProvider.notifier).startNew();
    return held;
  }

  /// Brings a held cart back into the POS. Throws [AppFailure] when the
  /// products cannot be re-checked (e.g. offline); the held cart is then
  /// left untouched.
  Future<ResumeReport> resume(String id) async {
    final repo = _repo;
    if (repo == null) throw const HoldException('Sesi belum siap.');
    final checkoutState = ref.read(checkoutControllerProvider);
    if (checkoutState.phase != CheckoutPhase.editing) {
      throw const HoldException('Selesaikan pembayaran yang sedang diproses terlebih dahulu.');
    }
    final held = (await future).where((c) => c.id == id).firstOrNull;
    if (held == null) throw const HoldException('Transaksi yang ditahan tidak ditemukan.');

    // 1. Re-read every product first; nothing changes if this fails.
    final catalog = ref.read(catalogRepositoryProvider);
    final fresh = <int, Product?>{};
    await Future.wait([
      for (final line in held.lines)
        () async {
          try {
            fresh[line.product.id] = await catalog.product(line.product.id);
          } on AppFailure catch (f) {
            if (f.kind != FailureKind.notFound) rethrow;
            fresh[line.product.id] = null; // deleted or moved out of this tenant
          }
        }(),
    ]);

    // 2. Keep whatever the cashier is working on.
    if (ref.read(cartControllerProvider).isNotEmpty) {
      await hold(note: 'Keranjang sebelumnya');
    }

    // 3. Rebuild the cart with current data.
    final cart = ref.read(cartControllerProvider.notifier)..clear();
    final money = ref.read(currencyFormatterProvider);
    final notes = <String>[];
    for (final line in held.lines) {
      final product = fresh[line.product.id];
      if (product == null || !product.isActive) {
        notes.add('${line.product.name} tidak tersedia lagi.');
        continue;
      }
      if (product.price != line.product.price) {
        notes.add(
          'Harga ${product.name} berubah: ${money.format(line.product.price)} → ${money.format(product.price)}.',
        );
      }
      final result = cart.add(product, qty: line.qty);
      if (result.change == CartChange.outOfStock) {
        notes.add('${product.name} sedang habis stok.');
      } else if (result.change == CartChange.stockLimited) {
        notes.add('Stok ${product.name} tinggal ${product.stock}.');
      }
    }
    ref.read(checkoutControllerProvider.notifier).setCustomer(held.customer);

    // 4. It is now the active cart.
    final next = [for (final c in await future) if (c.id != id) c];
    await repo.save(next);
    state = AsyncData(next);
    return ResumeReport(notes);
  }

  Future<void> discard(String id) async {
    final repo = _repo;
    if (repo == null) return;
    final next = [for (final c in await future) if (c.id != id) c];
    await repo.save(next);
    state = AsyncData(next);
  }
}

final heldCartsControllerProvider =
    AsyncNotifierProvider<HeldCartsController, List<HeldCart>>(HeldCartsController.new);
