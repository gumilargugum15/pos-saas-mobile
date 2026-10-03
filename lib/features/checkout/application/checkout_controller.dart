import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/app_failure.dart';
import '../../../data/repositories/sales_repository_impl.dart';
import '../../../domain/entities/cart.dart';
import '../../../domain/entities/party.dart';
import '../../../domain/entities/sale.dart';
import '../../../domain/repositories/sales_repository.dart';
import '../../auth/application/session_controller.dart';
import '../../cart/application/cart_controller.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../outlet/outlet_controller.dart';
import '../../products/application/catalog_controller.dart';

enum CheckoutPhase {
  editing,

  /// A request is in flight; the pay button is disabled.
  submitting,

  /// The request may have reached the server but no answer came back.
  unknown,
  success,
}

class CheckoutState {
  const CheckoutState({
    this.customer,
    this.paymentMethod,
    this.cashReceived,
    this.phase = CheckoutPhase.editing,
    this.sale,
    this.replayed = false,
    this.failure,
    this.recent,
    this.isCheckingRecent = false,
  });

  /// Null = walk-in.
  final Customer? customer;
  final PaymentMethod? paymentMethod;

  /// Whole rupiah received in cash. Ignored for non-cash methods.
  final int? cashReceived;
  final CheckoutPhase phase;
  final Sale? sale;
  final bool replayed;
  final AppFailure? failure;

  /// Recent server sales, fetched to resolve an unknown outcome.
  final RecentSales? recent;
  final bool isCheckingRecent;

  bool get isSubmitting => phase == CheckoutPhase.submitting;

  CheckoutState copyWith({
    Customer? customer,
    bool clearCustomer = false,
    PaymentMethod? paymentMethod,
    int? cashReceived,
    bool clearCash = false,
    CheckoutPhase? phase,
    Sale? sale,
    bool? replayed,
    AppFailure? failure,
    bool clearFailure = false,
    RecentSales? recent,
    bool clearRecent = false,
    bool? isCheckingRecent,
  }) =>
      CheckoutState(
        customer: clearCustomer ? null : customer ?? this.customer,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        cashReceived: clearCash ? null : cashReceived ?? this.cashReceived,
        phase: phase ?? this.phase,
        sale: sale ?? this.sale,
        replayed: replayed ?? this.replayed,
        failure: clearFailure ? null : failure ?? this.failure,
        recent: clearRecent ? null : recent ?? this.recent,
        isCheckingRecent: isCheckingRecent ?? this.isCheckingRecent,
      );
}

/// Checkout: customer → payment → pay, safe against double taps, retries,
/// timeouts and slow servers.
///
/// - Only one request can be in flight.
/// - Each distinct checkout (cart + customer + outlet + payment) gets one
///   Idempotency-Key; re-sending the same checkout reuses it, so the backend
///   returns the already created sale instead of a second one.
/// - A response that never arrived is "unknown", never "failed": recent
///   server sales are checked before anything is sent again.
/// - The cart is only cleared once the server has confirmed the sale.
class CheckoutController extends Notifier<CheckoutState> {
  static const _uuid = Uuid();

  String? _lastFingerprint;
  String? _lastKey;

  @override
  CheckoutState build() {
    ref.watch(activeTenantProvider);
    _lastFingerprint = null;
    _lastKey = null;
    return const CheckoutState();
  }

  Cart get _cart => ref.read(cartControllerProvider);

  void setCustomer(Customer? customer) {
    if (_locked) return;
    state = customer == null
        ? state.copyWith(clearCustomer: true, clearFailure: true)
        : state.copyWith(customer: customer, clearFailure: true);
  }

  void setPaymentMethod(PaymentMethod method) {
    if (_locked) return;
    state = state.copyWith(paymentMethod: method, clearFailure: true);
  }

  void setCashReceived(int? rupiah) {
    if (_locked) return;
    state = rupiah == null ? state.copyWith(clearCash: true, clearFailure: true) : state.copyWith(cashReceived: rupiah, clearFailure: true);
  }

  /// What will be sent as `paid_amount`. Non-cash methods charge the total,
  /// rounded up to whole rupiah like the web POS.
  int paidRupiah(Cart cart) {
    final method = state.paymentMethod;
    if (method == null) return 0;
    return method.isCash ? (state.cashReceived ?? 0) : cart.grandTotal.rupiahCeil;
  }

  /// The reason checkout cannot be submitted yet, or null.
  String? blockingReason(Cart cart, OutletState? outlet) {
    if (cart.isEmpty) return 'Keranjang masih kosong.';
    if (outlet == null) return 'Memuat outlet...';
    if (outlet.needsSelection) return 'Pilih outlet terlebih dahulu.';
    final method = state.paymentMethod;
    if (method == null) return 'Pilih metode pembayaran.';
    if (method.isCash && (state.cashReceived ?? 0) < cart.grandTotal.rupiahCeil) {
      return 'Uang diterima kurang dari total.';
    }
    return null;
  }

  Future<void> submit() async {
    if (_locked) return;
    final cart = _cart;
    final outlet = ref.read(outletControllerProvider).value;
    final reason = blockingReason(cart, outlet);
    if (reason != null) {
      state = state.copyWith(failure: AppFailure(FailureKind.validation, reason));
      return;
    }

    final request = CheckoutRequest(
      items: cart.toSaleItems(),
      paymentMethod: state.paymentMethod!,
      paidRupiah: paidRupiah(cart),
      customerId: state.customer?.id,
      branchId: outlet!.requestBranchId,
    );
    await _send(request);
  }

  /// Re-sends the pending checkout with the same Idempotency-Key.
  Future<void> resend() async {
    if (state.phase != CheckoutPhase.unknown || _pending == null) return;
    await _send(_pending!);
  }

  /// Looks for the pending checkout among the latest server sales.
  Future<void> checkRecent() async {
    final key = _lastKey;
    if (state.phase != CheckoutPhase.unknown || key == null || state.isCheckingRecent) return;
    state = state.copyWith(isCheckingRecent: true);
    try {
      final outlet = ref.read(outletControllerProvider).value;
      final recent = await ref.read(salesRepositoryProvider).recent(branchId: outlet?.requestBranchId);
      final match = recent.sales.where((s) => s.clientReference == key).firstOrNull;
      if (match != null) {
        _complete(match, replayed: true);
      } else {
        state = state.copyWith(recent: recent, isCheckingRecent: false);
      }
    } on AppFailure catch (failure) {
      state = state.copyWith(isCheckingRecent: false, failure: failure);
    }
  }

  /// The cashier verified on the recent list that the sale was recorded
  /// (backend without idempotency support).
  void confirmRecorded(Sale sale) {
    if (state.phase != CheckoutPhase.unknown) return;
    _complete(sale, replayed: true);
  }

  /// Back to editing after an unknown outcome, keeping the same key so a
  /// later identical submit is still deduplicated.
  void dismissUnknown() {
    if (state.phase != CheckoutPhase.unknown) return;
    state = state.copyWith(phase: CheckoutPhase.editing, clearRecent: true);
  }

  /// After a successful sale: ready for the next customer.
  void startNew() {
    _lastFingerprint = null;
    _lastKey = null;
    _pending = null;
    state = const CheckoutState();
  }

  CheckoutRequest? _pending;

  bool get _locked => state.phase == CheckoutPhase.submitting || state.phase == CheckoutPhase.success;

  Future<void> _send(CheckoutRequest request) async {
    if (state.phase == CheckoutPhase.submitting) return;

    final fingerprint = request.fingerprint;
    if (fingerprint != _lastFingerprint || _lastKey == null) {
      _lastFingerprint = fingerprint;
      _lastKey = _uuid.v4();
    }
    _pending = request;
    state = state.copyWith(phase: CheckoutPhase.submitting, clearFailure: true, clearRecent: true);

    try {
      final result = await ref.read(salesRepositoryProvider).checkout(request, idempotencyKey: _lastKey!);
      _complete(result.sale, replayed: result.replayed);
    } on AppFailure catch (failure) {
      if (failure.mayHaveReachedServer) {
        state = state.copyWith(phase: CheckoutPhase.unknown, failure: failure);
        await checkRecent();
        return;
      }
      state = state.copyWith(phase: CheckoutPhase.editing, failure: failure);
      if (failure.kind == FailureKind.validation) {
        // Stock or price may have changed: refresh what the cashier sees.
        ref.invalidate(catalogControllerProvider);
      }
    }
  }

  void _complete(Sale sale, {required bool replayed}) {
    ref.read(cartControllerProvider.notifier).clear();
    ref.invalidate(catalogControllerProvider);
    ref.invalidate(dashboardSummaryProvider);
    _pending = null;
    state = state.copyWith(
      phase: CheckoutPhase.success,
      sale: sale,
      replayed: replayed,
      clearFailure: true,
      clearRecent: true,
      isCheckingRecent: false,
    );
  }
}

final checkoutControllerProvider = NotifierProvider<CheckoutController, CheckoutState>(CheckoutController.new);

/// Quick cash amounts for a total: exact amount first, then the next round
/// notes above it.
List<int> quickCashOptions(int totalRupiah) {
  if (totalRupiah <= 0) return const [];
  final options = <int>{totalRupiah};
  for (final step in const [5000, 10000, 20000, 50000, 100000]) {
    final rounded = ((totalRupiah + step - 1) ~/ step) * step;
    if (rounded > totalRupiah) options.add(rounded);
    if (options.length >= 5) break;
  }
  return options.toList()..sort();
}
