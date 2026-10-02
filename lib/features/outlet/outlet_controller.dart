import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/session_store.dart';
import '../../data/repositories/sales_repository_impl.dart';
import '../../domain/entities/party.dart';
import '../auth/application/session_controller.dart';

class OutletState {
  const OutletState({this.selected, this.options = const [], this.isFixed = false});

  /// The outlet sales are recorded for. Null when none is chosen yet or the
  /// tenant has no branches at all.
  final Branch? selected;
  final List<Branch> options;

  /// The user has a home branch: the backend forces it and ignores any
  /// other `branch_id` (Controller::resolveBranchId).
  final bool isFixed;

  bool get canChange => !isFixed && options.length > 1;

  /// A tenant with branches needs one chosen before checkout.
  bool get needsSelection => !isFixed && selected == null && options.isNotEmpty;

  /// Sent as `branch_id`. Null for fixed users (the server decides).
  int? get requestBranchId => isFixed ? null : selected?.id;
}

/// Effective outlet = `user.branch_id ?? chosen branch`, as in the web POS.
class OutletController extends AsyncNotifier<OutletState> {
  @override
  Future<OutletState> build() async {
    final user = ref.watch(currentUserProvider);
    final tenant = ref.watch(activeTenantProvider);
    if (user == null || tenant == null) return const OutletState();

    if (user.branchId != null) {
      return OutletState(
        selected: Branch(id: user.branchId!, name: user.branchName ?? 'Outlet #${user.branchId}'),
        isFixed: true,
      );
    }

    final options = await ref.watch(salesRepositoryProvider).branches();
    final session = ref.read(sessionStoreProvider);
    final selected = options.where((b) => b.id == session.branchId).firstOrNull ??
        (options.length == 1 ? options.single : null);
    if (selected?.id != session.branchId) await session.saveBranchId(selected?.id);
    return OutletState(selected: selected, options: options);
  }

  Future<void> select(Branch branch) async {
    final current = state.value;
    if (current == null || current.isFixed) return;
    await ref.read(sessionStoreProvider).saveBranchId(branch.id);
    state = AsyncData(OutletState(selected: branch, options: current.options));
  }
}

final outletControllerProvider = AsyncNotifierProvider<OutletController, OutletState>(OutletController.new);
