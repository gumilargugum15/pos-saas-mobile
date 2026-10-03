import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kagoem_pos_mobile/core/printing/escpos_encoder.dart';
import 'package:kagoem_pos_mobile/core/utils/currency_formatter.dart';
import 'package:kagoem_pos_mobile/core/utils/money.dart';
import 'package:kagoem_pos_mobile/domain/entities/sale.dart';
import 'package:kagoem_pos_mobile/features/receipt/receipt_formatter.dart';

Sale sale({String productName = 'Kopi Susu', Money discount = const Money.zero()}) => Sale(
      id: 55,
      invoiceNumber: 'TX-261003-00001',
      cashierName: 'Siti Kasir',
      branchName: 'Toko Pusat',
      createdAt: DateTime(2026, 10, 3, 10, 20),
      items: [
        SaleItem(
          productId: 1,
          productName: productName,
          qty: 2,
          price: Money.rupiah(10000),
          discount: discount,
          tax: Money.rupiah(2200),
          subtotal: Money.rupiah(22200) - discount,
        ),
      ],
      subtotal: Money.rupiah(20000),
      discount: discount,
      tax: Money.rupiah(2200),
      grandTotal: Money.rupiah(22200) - discount,
      paid: Money.rupiah(25000),
      change: Money.rupiah(2800) + discount,
      paymentMethod: 'cash',
      status: SaleStatus.paid,
    );

const header = ReceiptHeader(storeName: 'Kagoem POS', tenantName: 'Toko ABC');

void main() {
  setUpAll(() => initializeDateFormatting('id'));

  ReceiptFormatter formatter(PaperSize paper) => ReceiptFormatter(paper: paper, currency: const CurrencyFormatter());

  test('80mm receipt matches the web layout', () {
    final f = formatter(PaperSize.mm80);
    final text = f.toPlainText(f.format(sale(), header));

    expect(text, '''
                   Kagoem POS
                    Toko ABC
                   Toko Pusat
                03/10/2026 10:20
                TX-261003-00001
------------------------------------------------
Kasir: Siti Kasir
Pelanggan: Walk-in
------------------------------------------------
Kopi Susu
2 x Rp 10.000                          Rp 22.200
------------------------------------------------
Subtotal                               Rp 20.000
Diskon                                      Rp 0
Pajak                                   Rp 2.200
TOTAL                                  Rp 22.200
Tunai                                  Rp 25.000
Kembalian                               Rp 2.800
------------------------------------------------
        Terima kasih atas kunjungan Anda''');
  });

  test('58mm: every line fits 32 columns, long names wrap, discount shown negative', () {
    final f = formatter(PaperSize.mm58);
    final lines = f.format(
      sale(productName: 'Sampoerna Mild 16 Batang Kemasan Ekonomis Super Hemat', discount: Money.rupiah(1000)),
      header,
    );
    for (final l in lines) {
      expect(l.text.length, lessThanOrEqualTo(32), reason: '"${l.text}"');
    }
    final texts = lines.map((l) => l.text).toList();
    expect(texts, containsAllInOrder(['Sampoerna Mild 16 Batang Kemasan', 'Ekonomis Super Hemat']));
    expect(texts, contains('Diskon                 -Rp 1.000'));
    expect(lines.firstWhere((l) => l.text.startsWith('TOTAL')).bold, isTrue);
  });

  test('padLine truncates the label, never the amount', () {
    final f = formatter(PaperSize.mm58);
    final line = f.padLine('99 x Rp 1.234.567 (harga grosir khusus)', 'Rp 122.222.133');
    expect(line.length, 32);
    expect(line, endsWith(' Rp 122.222.133'));
  });

  test('paper size follows the backend setting values', () {
    expect(PaperSize.fromSetting('58mm'), PaperSize.mm58);
    expect(PaperSize.fromSetting('80mm'), PaperSize.mm80);
    expect(PaperSize.fromSetting(null), PaperSize.mm80);
  });

  group('EscPosEncoder', () {
    test('init, align, bold, text, feed and cut', () {
      final bytes = EscPosEncoder.encode(const [
        ReceiptLine('TOKO', align: LineAlign.center, bold: true),
        ReceiptLine('a'),
      ]);
      expect(bytes, [
        0x1b, 0x40, // init
        0x1b, 0x61, 1, // center
        0x1b, 0x45, 1, // bold on
        ...latin1.encode('TOKO'), 0x0a,
        0x1b, 0x61, 0, // left
        0x1b, 0x45, 0, // bold off
        0x61, 0x0a,
        0x0a, 0x0a, 0x0a, // feed
        0x1d, 0x56, 0x00, // cut
      ]);
    });

    test('characters outside the printer code page become "?"', () {
      final bytes = EscPosEncoder.encode(const [ReceiptLine('Kopi ☕ 咖啡 é')], feedLines: 0, cut: false);
      // init (2) + explicit left align (3) precede the text.
      expect(latin1.decode(bytes.sublist(5, bytes.length - 1)), 'Kopi ? ?? é');
    });

    test('a full receipt encodes the invoice and totals', () {
      final f = formatter(PaperSize.mm58);
      final bytes = EscPosEncoder.encode(f.format(sale(), header));
      final text = latin1.decode(bytes);
      expect(text, contains('TX-261003-00001'));
      expect(text, contains('Rp 22.200'));
      expect(bytes.sublist(bytes.length - 3), [0x1d, 0x56, 0x00]);
    });
  });
}
