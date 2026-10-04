import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback.dart';
import '../../../domain/entities/sale.dart';
import '../../checkout/presentation/sale_success_page.dart';
import '../../settings/settings_providers.dart';
import '../application/transactions_controller.dart';

final _time = DateFormat('HH:mm');
final _dateTime = DateFormat('dd MMM yyyy, HH:mm', 'id');
final _shortDate = DateFormat('dd/MM', 'id');

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) ref.read(transactionsControllerProvider.notifier).loadMore();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  TransactionsController get _controller => ref.read(transactionsControllerProvider.notifier);

  Future<void> _pickDate(TransactionsFilter filter, DatePreset preset) async {
    if (preset != DatePreset.custom) {
      _controller.setFilter(filter.copyWith(datePreset: preset));
      return;
    }
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: filter.customRange,
    );
    if (range != null) _controller.setFilter(filter.copyWith(datePreset: DatePreset.custom, customRange: range));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionsControllerProvider);
    final filter = state.filter;
    final custom = filter.customRange;

    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat Transaksi')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(hintText: 'Cari nomor invoice', prefixIcon: Icon(Icons.search)),
                onChanged: (value) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), () {
                    _controller.setFilter(
                      ref.read(transactionsControllerProvider).filter.copyWith(search: value.trim()),
                    );
                  });
                },
              ),
            ),
            if (ref.watch(appConfigProvider).salesDateFilter)
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final preset in DatePreset.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            preset == DatePreset.custom && custom != null
                                ? '${_shortDate.format(custom.start)}–${_shortDate.format(custom.end)}'
                                : preset.label,
                          ),
                          selected: filter.datePreset == preset,
                          onSelected: (_) => _pickDate(filter, preset),
                        ),
                      ),
                  ],
                ),
              ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _FilterMenu<PaymentMethod>(
                    label: filter.paymentMethod?.label ?? 'Semua metode',
                    active: filter.paymentMethod != null,
                    options: PaymentMethod.values,
                    optionLabel: (m) => m.label,
                    onSelected: (m) => _controller.setFilter(
                      m == null ? filter.copyWith(clearPaymentMethod: true) : filter.copyWith(paymentMethod: m),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _FilterMenu<SaleStatus>(
                    label: filter.status?.label ?? 'Semua status',
                    active: filter.status != null,
                    options: SaleStatus.values,
                    optionLabel: (s) => s.label,
                    onSelected: (s) => _controller.setFilter(
                      s == null ? filter.copyWith(clearStatus: true) : filter.copyWith(status: s),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildList(state)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(TransactionsState state) {
    if (state.isLoading) return const Center(child: CircularProgressIndicator());
    if (state.failure != null && state.items.isEmpty) {
      return StatusView(
        icon: Icons.cloud_off,
        message: state.failure!.message,
        actionLabel: 'Coba Lagi',
        onAction: _controller.refresh,
      );
    }
    if (state.items.isEmpty) {
      return const StatusView(icon: Icons.receipt_long, message: 'Tidak ada transaksi untuk filter ini.');
    }
    return RefreshIndicator(
      onRefresh: _controller.refresh,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.items.length + 1,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i == state.items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: state.isLoadingMore
                    ? const CircularProgressIndicator()
                    : Text('${state.total} transaksi', style: Theme.of(context).textTheme.bodySmall),
              ),
            );
          }
          return _SaleTile(sale: state.items[i]);
        },
      ),
    );
  }
}

class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    required this.label,
    required this.active,
    required this.options,
    required this.optionLabel,
    required this.onSelected,
  });

  final String label;
  final bool active;
  final List<T> options;
  final String Function(T) optionLabel;
  final void Function(T?) onSelected;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(onPressed: () => onSelected(null), child: const Text('Semua')),
        for (final o in options) MenuItemButton(onPressed: () => onSelected(o), child: Text(optionLabel(o))),
      ],
      builder: (context, controller, _) => FilterChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

class _SaleTile extends ConsumerWidget {
  const _SaleTile({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(sale.invoiceNumber, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        [if (sale.createdAt != null) _time.format(sale.createdAt!), sale.paymentLabel, sale.customerLabel].join(' · '),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(ref.money(sale.grandTotal), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          SaleStatusBadge(status: sale.status),
        ],
      ),
      onTap: () => context.push('/transactions/${sale.id}'),
    );
  }
}

class SaleStatusBadge extends StatelessWidget {
  const SaleStatusBadge({super.key, required this.status});

  final SaleStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      SaleStatus.paid => BrandColors.success,
      SaleStatus.refunded || SaleStatus.voided => scheme.error,
      SaleStatus.pending => BrandColors.warning,
    };
    return Text(
      status.label.toUpperCase(),
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
    );
  }
}

class TransactionDetailPage extends ConsumerWidget {
  const TransactionDetailPage({super.key, required this.saleId});

  final int saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sale = ref.watch(saleDetailProvider(saleId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Transaksi'),
        actions: [
          IconButton(
            key: const Key('open-receipt'),
            tooltip: 'Struk (cetak ulang / bagikan)',
            onPressed: () => context.push('/transactions/$saleId/receipt'),
            icon: const Icon(Icons.receipt_long),
          ),
        ],
      ),
      body: SafeArea(
        child: sale.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => StatusView(
            icon: Icons.cloud_off,
            message: e is AppFailure ? e.message : 'Gagal memuat transaksi.',
            actionLabel: 'Coba Lagi',
            onAction: () => ref.invalidate(saleDetailProvider(saleId)),
          ),
          data: (sale) => _SaleDetail(sale: sale),
        ),
      ),
    );
  }
}

class _SaleDetail extends ConsumerWidget {
  const _SaleDetail({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    Widget row(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: strong ? textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900) : null),
        ],
      ),
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(sale.invoiceNumber, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ),
                SaleStatusBadge(status: sale.status),
              ],
            ),
            const SizedBox(height: 4),
            if (sale.createdAt != null) Text(_dateTime.format(sale.createdAt!)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    row('Kasir', sale.cashierName ?? '-'),
                    row('Pelanggan', sale.customerLabel),
                    row('Outlet', sale.branchName ?? '-'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final item in sale.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.productName, style: textTheme.titleSmall),
                                  Text('${ref.money(item.price)} × ${item.qty}', style: textTheme.bodySmall),
                                ],
                              ),
                            ),
                            Text(ref.money(item.subtotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    const Divider(),
                    row('Subtotal', ref.money(sale.subtotal)),
                    row('Diskon', sale.discount.isZero ? ref.money(sale.discount) : '-${ref.money(sale.discount)}'),
                    row('Pajak', ref.money(sale.tax)),
                    row('Total', ref.money(sale.grandTotal), strong: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SaleSummaryCard(sale: sale),
          ],
        ),
      ),
    );
  }
}
