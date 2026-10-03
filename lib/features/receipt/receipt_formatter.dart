import 'package:intl/intl.dart';

import '../../core/utils/currency_formatter.dart';
import '../../domain/entities/sale.dart';

enum PaperSize {
  mm58('58mm', 32),
  mm80('80mm', 48);

  const PaperSize(this.label, this.columns);

  /// Value used by the backend setting `receipt_paper_size`.
  final String label;

  /// Characters per line in the printer's standard font.
  final int columns;

  static PaperSize fromSetting(String? value) => value == '58mm' ? PaperSize.mm58 : PaperSize.mm80;
}

enum LineAlign { left, center }

class ReceiptLine {
  const ReceiptLine(this.text, {this.align = LineAlign.left, this.bold = false});

  final String text;
  final LineAlign align;
  final bool bold;
}

/// Store identity printed at the top. `company_name` is a global backend
/// setting, so the tenant and outlet are printed under it (decision D5).
class ReceiptHeader {
  const ReceiptHeader({required this.storeName, this.tenantName, this.outletName});

  final String storeName;
  final String? tenantName;
  final String? outletName;
}

/// Lays out a sale as fixed-width receipt lines, matching the web POS
/// receipt (frontend/src/lib/escpos.ts) so both print the same thing.
/// Pure: the same lines feed the preview, sharing and the ESC/POS encoder.
class ReceiptFormatter {
  ReceiptFormatter({required this.paper, required this.currency});

  final PaperSize paper;
  final CurrencyFormatter currency;

  static final _date = DateFormat('dd/MM/yyyy HH:mm', 'id');
  static const footer = 'Terima kasih atas kunjungan Anda';

  int get width => paper.columns;

  List<ReceiptLine> format(Sale sale, ReceiptHeader header) {
    final lines = <ReceiptLine>[];
    void center(String text, {bool bold = false}) {
      for (final part in _wrap(text)) {
        lines.add(ReceiptLine(part, align: LineAlign.center, bold: bold));
      }
    }

    void left(String text, {bool bold = false}) {
      for (final part in _wrap(text)) {
        lines.add(ReceiptLine(part, bold: bold));
      }
    }

    void pair(String label, String value, {bool bold = false}) => lines.add(ReceiptLine(padLine(label, value), bold: bold));
    void divider() => lines.add(ReceiptLine('-' * width));

    center(header.storeName, bold: true);
    final tenant = header.tenantName;
    if (tenant != null && tenant.isNotEmpty && tenant != header.storeName) center(tenant);
    final outlet = header.outletName ?? sale.branchName;
    if (outlet != null && outlet.isNotEmpty) center(outlet);
    if (sale.createdAt != null) center(_date.format(sale.createdAt!));
    center(sale.invoiceNumber);
    divider();
    left('Kasir: ${sale.cashierName ?? '-'}');
    left('Pelanggan: ${sale.customerLabel}');
    divider();

    for (final item in sale.items) {
      left(item.productName);
      pair('${item.qty} x ${currency.format(item.price)}', currency.format(item.subtotal));
    }

    divider();
    pair('Subtotal', currency.format(sale.subtotal));
    pair('Diskon', sale.discount.isZero ? currency.format(sale.discount) : '-${currency.format(sale.discount)}');
    pair('Pajak', currency.format(sale.tax));
    pair('TOTAL', currency.format(sale.grandTotal), bold: true);
    pair(sale.paymentLabel, currency.format(sale.paid));
    pair('Kembalian', currency.format(sale.change));
    divider();
    center(footer);
    return lines;
  }

  List<ReceiptLine> testPage() => [
        ReceiptLine('TEST PRINT', align: LineAlign.center, bold: true),
        ReceiptLine('-' * width),
        const ReceiptLine('Printer berhasil terhubung'),
        const ReceiptLine('dan siap digunakan.'),
        ReceiptLine('Lebar kertas: ${paper.label}'),
        ReceiptLine(_date.format(DateTime.now())),
      ];

  /// Plain text (monospace) for the preview and for sharing.
  String toPlainText(List<ReceiptLine> lines) => lines
      .map((l) => l.align == LineAlign.center ? centerText(l.text) : l.text)
      .join('\n');

  /// `label ……… value`, truncating the label so the value always fits.
  String padLine(String label, String value) {
    final maxLabel = (width - value.length - 1).clamp(0, width);
    final left = label.length > maxLabel ? label.substring(0, maxLabel) : label;
    return left + ' ' * (width - left.length - value.length).clamp(1, width) + value;
  }

  String centerText(String text) {
    if (text.length >= width) return text;
    return ' ' * ((width - text.length) ~/ 2) + text;
  }

  /// Word-wraps to the paper width; words longer than a line are split.
  List<String> _wrap(String text) {
    final result = <String>[];
    var current = '';
    for (final word in text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
      var w = word;
      while (w.length > width) {
        if (current.isNotEmpty) {
          result.add(current);
          current = '';
        }
        result.add(w.substring(0, width));
        w = w.substring(width);
      }
      if (current.isEmpty) {
        current = w;
      } else if (current.length + 1 + w.length <= width) {
        current = '$current $w';
      } else {
        result.add(current);
        current = w;
      }
    }
    if (current.isNotEmpty || result.isEmpty) result.add(current);
    return result;
  }
}
