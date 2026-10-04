import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/storage/session_store.dart';
import '../../core/utils/json.dart';
import '../../domain/entities/cart.dart';
import '../../domain/entities/held_cart.dart';
import '../../domain/entities/party.dart';
import '../models/catalog_models.dart';

/// Held carts of one cashier in one tenant, stored on this device.
///
/// Scoped by tenant *and* user so cashiers sharing a till never see each
/// other's parked carts, and data never crosses tenants. Kept across
/// logout on purpose: a cashier can log out for a break and resume later.
class HeldCartRepository {
  HeldCartRepository(this._store, {required int tenantId, required int userId})
      : _key = 'kagoem.held_carts.t$tenantId.u$userId';

  static const maxHeld = 20;

  final SecureKeyValueStore _store;
  final String _key;

  Future<List<HeldCart>> load() async {
    try {
      final raw = await _store.read(_key);
      if (raw == null || raw.isEmpty) return [];
      return [for (final item in jsonDecode(raw) as List) _decode(Json.asMap(item))];
    } catch (e) {
      // A corrupt entry must not block the till; start over.
      debugPrint('Held carts unreadable, resetting: $e');
      return [];
    }
  }

  Future<void> save(List<HeldCart> carts) async {
    if (carts.isEmpty) {
      await _store.delete(_key);
    } else {
      await _store.write(_key, jsonEncode([for (final c in carts) _encode(c)]));
    }
  }

  static Map<String, dynamic> _encode(HeldCart c) => {
        'id': c.id,
        'note': c.note,
        'created_at': c.createdAt.toUtc().toIso8601String(),
        'customer': c.customer == null ? null : {'id': c.customer!.id, 'name': c.customer!.name},
        'lines': [
          for (final l in c.lines) {'qty': l.qty, 'product': ProductModel.toJson(l.product)},
        ],
      };

  static HeldCart _decode(Map<String, dynamic> json) {
    final customer = json['customer'];
    return HeldCart(
      id: Json.asString(json['id']),
      note: Json.asStringOrNull(json['note']),
      createdAt: DateTime.tryParse(Json.asString(json['created_at']))?.toLocal() ?? DateTime.now(),
      customer: customer is Map
          ? Customer(id: Json.asInt(customer['id']), name: Json.asString(customer['name']))
          : null,
      lines: [
        for (final l in json['lines'] as List)
          CartLine(product: ProductModel.fromJson(Json.asMap((l as Map)['product'])), qty: Json.asInt(l['qty'])),
      ],
    );
  }
}
