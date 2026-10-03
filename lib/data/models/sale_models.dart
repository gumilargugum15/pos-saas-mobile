import '../../core/utils/json.dart';
import '../../core/utils/money.dart';
import '../../domain/entities/party.dart';
import '../../domain/entities/sale.dart';

/// Parses `SaleResource` / `SaleItemResource`.
abstract final class SaleModel {
  static Sale fromJson(Map<String, dynamic> json) {
    final customer = json['customer'];
    return Sale(
      id: Json.asInt(json['id']),
      invoiceNumber: Json.asString(json['invoice_number']),
      clientReference: Json.asStringOrNull(json['client_reference']),
      branchId: Json.asIntOrNull(json['branch_id']),
      branchName: Json.asStringOrNull(json['branch_name']),
      customerId: customer is Map ? Json.asIntOrNull(customer['id']) : null,
      customerName: customer is Map ? Json.asStringOrNull(customer['name']) : null,
      cashierName: Json.asStringOrNull(json['cashier_name']),
      items: [
        if (json['items'] is List)
          for (final item in json['items'] as List) _item(Json.asMap(item)),
      ],
      subtotal: Money.fromJson(json['subtotal']),
      discount: Money.fromJson(json['discount_amount']),
      tax: Money.fromJson(json['tax_amount']),
      grandTotal: Money.fromJson(json['grand_total']),
      paid: Money.fromJson(json['paid_amount']),
      change: Money.fromJson(json['change_amount']),
      paymentMethod: Json.asString(json['payment_method']),
      status: SaleStatus.fromApi(Json.asStringOrNull(json['status'])),
      createdAt: DateTime.tryParse(Json.asString(json['created_at']))?.toLocal(),
    );
  }

  static SaleItem _item(Map<String, dynamic> json) => SaleItem(
        productId: Json.asInt(json['product_id']),
        productName: Json.asString(json['product_name']),
        qty: Json.asInt(json['qty']),
        price: Money.fromJson(json['price']),
        discount: Money.fromJson(json['discount_amount']),
        tax: Money.fromJson(json['tax_amount']),
        subtotal: Money.fromJson(json['subtotal']),
      );
}

abstract final class BranchModel {
  static Branch fromJson(Map<String, dynamic> json) => Branch(
        id: Json.asInt(json['id']),
        name: Json.asString(json['name']),
        code: Json.asStringOrNull(json['code']),
        address: Json.asStringOrNull(json['address']),
        phone: Json.asStringOrNull(json['phone']),
      );
}

abstract final class CustomerModel {
  static Customer fromJson(Map<String, dynamic> json) => Customer(
        id: Json.asInt(json['id']),
        name: Json.asString(json['name']),
        phone: Json.asStringOrNull(json['phone']),
        email: Json.asStringOrNull(json['email']),
        address: Json.asStringOrNull(json['address']),
      );
}
