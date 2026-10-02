import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagoem_pos_mobile/core/utils/money.dart';
import 'package:kagoem_pos_mobile/domain/entities/tenant.dart';
import 'package:kagoem_pos_mobile/features/auth/application/session_controller.dart';
import 'package:kagoem_pos_mobile/features/cart/application/cart_controller.dart';

import '../../domain/cart_test.dart' show product;

void main() {
  late ProviderContainer container;
  late CartController cart;

  setUp(() {
    container = ProviderContainer(
      overrides: [activeTenantProvider.overrideWithValue(const Tenant(id: 1, name: 'Toko ABC'))],
    );
    cart = container.read(cartControllerProvider.notifier);
  });

  tearDown(() => container.dispose());

  int qty(int id) => container.read(cartControllerProvider).qtyOf(id);

  test('add, add again, increment', () {
    expect(cart.add(product(id: 1)).change, CartChange.added);
    expect(cart.add(product(id: 1)).change, CartChange.updated);
    cart.increment(1);
    expect(qty(1), 3);
    expect(container.read(cartControllerProvider).lines, hasLength(1));
  });

  test('decrement to zero removes the line', () {
    cart.add(product(id: 1));
    expect(cart.decrement(1).change, CartChange.removed);
    expect(container.read(cartControllerProvider).isEmpty, isTrue);
  });

  test('manual quantity, and 0 removes', () {
    cart.add(product(id: 1));
    cart.setQty(1, 7);
    expect(qty(1), 7);
    cart.setQty(1, 0);
    expect(qty(1), 0);
  });

  test('out-of-stock products cannot be added', () {
    final result = cart.add(product(id: 5, stock: 0));
    expect(result.change, CartChange.outOfStock);
    expect(result.message, 'P5 sedang habis stok.');
    expect(container.read(cartControllerProvider).isEmpty, isTrue);
  });

  test('quantity is limited to the known stock with a message', () {
    cart.add(product(id: 1, stock: 2));
    cart.add(product(id: 1, stock: 2));
    final result = cart.increment(1);
    expect(result.change, CartChange.stockLimited);
    expect(result.message, 'Stok P1 tidak mencukupi (tersisa 2).');
    expect(qty(1), 2);

    expect(cart.setQty(1, 50).change, CartChange.stockLimited);
    expect(qty(1), 2);
  });

  test('remove and clear', () {
    cart.add(product(id: 1));
    cart.add(product(id: 2));
    cart.remove(1);
    expect(container.read(cartControllerProvider).lines.single.product.id, 2);
    cart.clear();
    expect(container.read(cartControllerProvider).isEmpty, isTrue);
  });

  test('total updates with quantity', () {
    cart.add(product(id: 1, price: 10000, tax: 0));
    cart.add(product(id: 2, price: 15000, tax: 0));
    cart.increment(1);
    expect(container.read(cartControllerProvider).grandTotal, Money.rupiah(35000));
  });

  test('fresher catalog data updates price snapshots in the cart', () {
    cart.add(product(id: 1, price: 10000));
    cart.syncProducts([product(id: 1, price: 12000), product(id: 9)]);
    final line = container.read(cartControllerProvider).lines.single;
    expect(line.product.price, Money.rupiah(12000));
  });
}
