import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/shift_repository_impl.dart';
import '../../domain/entities/shift.dart';
import '../auth/application/session_controller.dart';
import '../outlet/outlet_controller.dart';

class ShiftOverview {
  const ShiftOverview({this.shift, this.live, this.movements = const [], this.justClosed});

  /// The user's open shift, if any.
  final Shift? shift;
  final ShiftLive? live;

  /// Cash in/out of the open shift, newest first.
  final List<CashMovement> movements;

  /// The shift closed in this session, to show its result once.
  final Shift? justClosed;

  bool get isOpen => shift != null;
}

/// The cashier's drawer: open shift → record cash in/out → close with a
/// physical count. Selling does not require an open shift (as in the web
/// POS). Writes throw `AppFailure`; state is re-read from the server after
/// every successful write, so totals always come from the backend.
class ShiftController extends AsyncNotifier<ShiftOverview> {
  ShiftRepository get _repo => ref.read(shiftRepositoryProvider);

  @override
  Future<ShiftOverview> build() async {
    final capabilities = ref.watch(cashierCapabilitiesProvider);
    if (capabilities == null || !capabilities.canUseCashDrawer) return const ShiftOverview();
    ref.watch(shiftRepositoryProvider);
    return _load();
  }

  Future<void> refresh() async {
    state = AsyncData(await _load(justClosed: state.value?.justClosed));
  }

  Future<void> open({required int openingRupiah, String? notes}) async {
    final outlet = await ref.read(outletControllerProvider.future);
    await _repo.open(openingRupiah: openingRupiah, notes: notes, branchId: outlet.requestBranchId);
    state = AsyncData(await _load());
  }

  Future<void> record({required CashCategory category, required int amountRupiah, required String description}) async {
    final outlet = await ref.read(outletControllerProvider.future);
    await _repo.record(
      category: category,
      amountRupiah: amountRupiah,
      description: description,
      branchId: outlet.requestBranchId,
    );
    state = AsyncData(await _load());
  }

  Future<Shift> close({required int closingRupiah, String? notes}) async {
    final shift = state.value?.shift;
    if (shift == null) throw StateError('No open shift');
    final closed = await _repo.close(shift.id, closingRupiah: closingRupiah, notes: notes);
    state = AsyncData(await _load(justClosed: closed));
    return closed;
  }

  void dismissClosed() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(ShiftOverview(shift: current.shift, live: current.live, movements: current.movements));
  }

  Future<ShiftOverview> _load({Shift? justClosed}) async {
    final current = await _repo.current();
    final shift = current.shift;
    final movements = shift == null ? const <CashMovement>[] : await _repo.movements(shift.id);
    return ShiftOverview(shift: shift, live: current.live, movements: movements, justClosed: justClosed);
  }
}

final shiftControllerProvider = AsyncNotifierProvider<ShiftController, ShiftOverview>(ShiftController.new);
