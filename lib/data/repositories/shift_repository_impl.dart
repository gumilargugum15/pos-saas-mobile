import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/json.dart';
import '../../core/utils/money.dart';
import '../../domain/entities/shift.dart';
import '../../features/auth/application/session_controller.dart';

/// `/shifts` and `/cash-transactions` (permission `operate-cash-drawer`).
/// Every method throws `AppFailure` on error.
class ShiftRepository {
  ShiftRepository(this._api);

  final ApiClient _api;

  /// The user's open shift with live totals, or nulls when none is open.
  Future<({Shift? shift, ShiftLive? live})> current() async {
    final response = await _api.get('/shifts/current', parse: (d) {
      final json = Json.asMap(d);
      final shift = json['shift'];
      final live = json['live'];
      return (
        shift: shift is Map ? _shift(Json.asMap(shift)) : null,
        live: live is Map ? _live(Json.asMap(live)) : null,
      );
    });
    return response.data;
  }

  Future<Shift> open({required int openingRupiah, String? notes, int? branchId}) async {
    final response = await _api.post(
      '/shifts',
      body: {'branch_id': branchId, 'opening_balance': openingRupiah, 'notes': _blank(notes)},
      parse: (d) => _shift(Json.asMap(d)),
    );
    return response.data;
  }

  Future<Shift> close(int shiftId, {required int closingRupiah, String? notes}) async {
    final response = await _api.post(
      '/shifts/$shiftId/close',
      body: {'closing_balance': closingRupiah, 'notes': _blank(notes)},
      parse: (d) => _shift(Json.asMap(d)),
    );
    return response.data;
  }

  Future<List<CashMovement>> movements(int shiftId) async {
    final page = await _api.getPage(
      '/cash-transactions',
      query: {'shift_id': shiftId, 'sort': 'created_at', 'direction': 'desc', 'per_page': 50},
      parseItem: _movement,
    );
    return page.items;
  }

  /// The server attaches it to the user's open shift (422 when none is open).
  Future<CashMovement> record({
    required CashCategory category,
    required int amountRupiah,
    required String description,
    int? branchId,
  }) async {
    final response = await _api.post(
      '/cash-transactions',
      body: {
        'branch_id': branchId,
        'type': category.direction.apiValue,
        'category': category.apiValue,
        'amount': amountRupiah,
        'description': description.trim(),
      },
      parse: (d) => _movement(Json.asMap(d)),
    );
    return response.data;
  }

  static String? _blank(String? v) => v == null || v.trim().isEmpty ? null : v.trim();

  static Money? _moneyOrNull(Object? v) => v == null ? null : Money.fromJson(v);

  static Shift _shift(Map<String, dynamic> json) => Shift(
        id: Json.asInt(json['id']),
        isOpen: json['status'] == 'open',
        openingBalance: Money.fromJson(json['opening_balance']),
        closingBalance: _moneyOrNull(json['closing_balance']),
        expectedBalance: _moneyOrNull(json['expected_balance']),
        variance: _moneyOrNull(json['variance']),
        openedAt: DateTime.tryParse(Json.asString(json['opened_at']))?.toLocal(),
        closedAt: DateTime.tryParse(Json.asString(json['closed_at']))?.toLocal(),
        branchName: Json.asStringOrNull(json['branch_name']),
        userName: Json.asStringOrNull(json['user_name']),
        notes: Json.asStringOrNull(json['notes']),
      );

  static ShiftLive _live(Map<String, dynamic> json) => ShiftLive(
        cashSales: Money.fromJson(json['cash_sales']),
        cashIn: Money.fromJson(json['cash_in_total']),
        cashOut: Money.fromJson(json['cash_out_total']),
        expectedBalance: Money.fromJson(json['expected_balance']),
      );

  static CashMovement _movement(Map<String, dynamic> json) => CashMovement(
        id: Json.asInt(json['id']),
        referenceNumber: Json.asString(json['reference_number']),
        type: Json.asString(json['type']),
        category: Json.asString(json['category']),
        amount: Money.fromJson(json['amount']),
        description: Json.asString(json['description']),
        createdAt: DateTime.tryParse(Json.asString(json['created_at']))?.toLocal(),
      );
}

final shiftRepositoryProvider = Provider<ShiftRepository>((ref) {
  ref.watch(activeTenantProvider);
  return ShiftRepository(ref.watch(apiClientProvider));
});
