import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/error/app_failure.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/rupiah_input.dart';
import '../../domain/entities/shift.dart';
import '../settings/settings_providers.dart';
import 'shift_controller.dart';

final _time = DateFormat('HH:mm');
final _dateTime = DateFormat('dd MMM yyyy, HH:mm', 'id');

class ShiftPage extends ConsumerWidget {
  const ShiftPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(shiftControllerProvider);
    final controller = ref.read(shiftControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Shift & Kas')),
      body: SafeArea(
        child: overview.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => StatusView(
            icon: Icons.cloud_off,
            message: e is AppFailure ? e.message : 'Data shift tidak dapat dimuat.',
            actionLabel: 'Coba Lagi',
            onAction: () => ref.invalidate(shiftControllerProvider),
          ),
          data: (o) => RefreshIndicator(
            onRefresh: controller.refresh,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (o.justClosed != null) ...[
                      _ClosedResult(shift: o.justClosed!, onDone: controller.dismissClosed),
                      const SizedBox(height: 16),
                    ],
                    if (o.shift == null) const _NoShift() else _OpenShift(overview: o),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoShift extends StatelessWidget {
  const _NoShift();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.lock_clock, size: 48),
            const SizedBox(height: 12),
            Text(
              'Belum ada shift aktif',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Buka shift dengan saldo awal laci kas untuk mencatat kas masuk/keluar dan menutup kas di akhir shift.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('shift-open'),
              onPressed: () => _showSheet(context, const _OpenShiftForm()),
              icon: const Icon(Icons.lock_open),
              label: const Text('BUKA SHIFT'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenShift extends ConsumerWidget {
  const _OpenShift({required this.overview});

  final ShiftOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shift = overview.shift!;
    final live = overview.live;
    final textTheme = Theme.of(context).textTheme;
    Widget row(String label, Money value, {bool strong = false, String sign = ''}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Text(label, style: strong ? textTheme.titleMedium : null),
              const SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$sign${ref.money(value)}',
                    style: strong
                        ? textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)
                        : textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.circle, size: 12, color: BrandColors.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Shift aktif sejak ${shift.openedAt == null ? '-' : _time.format(shift.openedAt!)}',
                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                if (shift.branchName != null) Text(shift.branchName!),
                const Divider(height: 24),
                row('Saldo awal', shift.openingBalance),
                if (live != null) ...[
                  row('Penjualan tunai', live.cashSales, sign: '+'),
                  row('Kas masuk', live.cashIn, sign: '+'),
                  row('Kas keluar', live.cashOut, sign: '-'),
                  const Divider(height: 16),
                  row('Ekspektasi saldo', live.expectedBalance, strong: true),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('cash-record'),
                onPressed: () => _showSheet(context, const _CashMovementForm()),
                icon: const Icon(Icons.swap_vert),
                label: const Text('CATAT KAS'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                key: const Key('shift-close'),
                onPressed: () => _showSheet(context, _CloseShiftForm(expected: live?.expectedBalance)),
                icon: const Icon(Icons.lock),
                label: const Text('TUTUP SHIFT'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Kas masuk / keluar', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (overview.movements.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: Text('Belum ada catatan kas pada shift ini.'))
        else
          Card(
            child: Column(
              children: [
                for (final m in overview.movements)
                  ListTile(
                    leading: Icon(
                      m.isIn ? Icons.south_west : Icons.north_east,
                      color: m.isIn ? BrandColors.success : Theme.of(context).colorScheme.error,
                    ),
                    title: Text(m.description),
                    subtitle: Text(
                      [m.categoryLabel, if (m.createdAt != null) _time.format(m.createdAt!), m.referenceNumber].join(' · '),
                    ),
                    trailing: Text(
                      '${m.isIn ? '+' : '-'}${ref.money(m.amount)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ClosedResult extends ConsumerWidget {
  const _ClosedResult({required this.shift, required this.onDone});

  final Shift shift;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variance = shift.variance ?? const Money.zero();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (label, color) = variance.isZero
        ? ('Kas sesuai', BrandColors.success)
        : variance.isNegative
            ? ('Kas kurang', scheme.error)
            : ('Kas lebih', BrandColors.warning);

    return Card(
      key: const Key('shift-closed-result'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Shift ditutup', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            if (shift.closedAt != null) Text(_dateTime.format(shift.closedAt!)),
            const Divider(height: 24),
            _kv(context, 'Ekspektasi saldo', ref.money(shift.expectedBalance ?? const Money.zero())),
            _kv(context, 'Uang dihitung', ref.money(shift.closingBalance ?? const Money.zero())),
            _kv(context, 'Selisih', '${variance.isNegative ? '' : variance.isZero ? '' : '+'}${ref.money(variance)}'),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onDone, child: const Text('Selesai')),
          ],
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(k)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

Future<void> _showSheet(BuildContext context, Widget form) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: form,
      ),
    );

/// Shared busy/error handling for the shift forms: one submit at a time,
/// writes are never retried automatically.
mixin _SubmitOnce<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool busy = false;
  String? error;

  Future<void> submit(Future<void> Function() action, {required String success}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (!mounted) return;
      Navigator.pop(context);
      showQuickMessage(context, success);
    } on AppFailure catch (f) {
      if (!mounted) return;
      setState(() => error = f.mayHaveReachedServer
          ? 'Server tidak membalas. Tarik layar untuk memuat ulang dan periksa sebelum mencoba lagi.'
          : f.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _OpenShiftForm extends ConsumerStatefulWidget {
  const _OpenShiftForm();

  @override
  ConsumerState<_OpenShiftForm> createState() => _OpenShiftFormState();
}

class _OpenShiftFormState extends ConsumerState<_OpenShiftForm> with _SubmitOnce {
  final _amount = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = parseRupiahInput(_amount.text);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Buka Shift', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        if (error != null) ...[MessageBanner(error!), const SizedBox(height: 12)],
        TextField(
          key: const Key('shift-opening'),
          controller: _amount,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: const [RupiahInputFormatter()],
          decoration: const InputDecoration(labelText: 'Saldo awal laci kas', prefixText: 'Rp '),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Catatan (opsional)')),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('shift-open-submit'),
          onPressed: busy || amount == null
              ? null
              : () => submit(
                    () => ref.read(shiftControllerProvider.notifier).open(openingRupiah: amount, notes: _notes.text),
                    success: 'Shift dibuka.',
                  ),
          child: Text(busy ? 'Memproses...' : 'BUKA SHIFT'),
        ),
      ],
    );
  }
}

class _CashMovementForm extends ConsumerStatefulWidget {
  const _CashMovementForm();

  @override
  ConsumerState<_CashMovementForm> createState() => _CashMovementFormState();
}

class _CashMovementFormState extends ConsumerState<_CashMovementForm> with _SubmitOnce {
  final _amount = TextEditingController();
  final _description = TextEditingController();
  CashDirection _direction = CashDirection.cashIn;
  CashCategory _category = CashCategory.income;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = parseRupiahInput(_amount.text) ?? 0;
    final ready = amount > 0 && _description.text.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Catat Kas', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        if (error != null) ...[MessageBanner(error!), const SizedBox(height: 12)],
        SegmentedButton<CashDirection>(
          segments: [for (final d in CashDirection.values) ButtonSegment(value: d, label: Text(d.label))],
          selected: {_direction},
          onSelectionChanged: (s) => setState(() {
            _direction = s.first;
            _category = CashCategory.of(_direction).first;
          }),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in CashCategory.of(_direction))
              ChoiceChip(label: Text(c.label), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('cash-amount'),
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: const [RupiahInputFormatter()],
          decoration: const InputDecoration(labelText: 'Jumlah', prefixText: 'Rp '),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('cash-description'),
          controller: _description,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Keterangan *'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('cash-submit'),
          onPressed: busy || !ready
              ? null
              : () => submit(
                    () => ref.read(shiftControllerProvider.notifier).record(
                          category: _category,
                          amountRupiah: amount,
                          description: _description.text,
                        ),
                    success: '${_direction.label} dicatat.',
                  ),
          child: Text(busy ? 'Menyimpan...' : 'SIMPAN'),
        ),
      ],
    );
  }
}

class _CloseShiftForm extends ConsumerStatefulWidget {
  const _CloseShiftForm({required this.expected});

  final Money? expected;

  @override
  ConsumerState<_CloseShiftForm> createState() => _CloseShiftFormState();
}

class _CloseShiftFormState extends ConsumerState<_CloseShiftForm> with _SubmitOnce {
  final _counted = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _counted.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final counted = parseRupiahInput(_counted.text);
    final expected = widget.expected;
    // Preview only; the server computes the recorded variance.
    final variance = counted == null || expected == null ? null : Money.rupiah(counted) - expected;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Tutup Shift', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (expected != null) Text('Ekspektasi saldo: ${ref.money(expected)}'),
        const SizedBox(height: 16),
        if (error != null) ...[MessageBanner(error!), const SizedBox(height: 12)],
        TextField(
          key: const Key('shift-counted'),
          controller: _counted,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: const [RupiahInputFormatter()],
          decoration: const InputDecoration(labelText: 'Uang fisik di laci', prefixText: 'Rp '),
          onChanged: (_) => setState(() {}),
        ),
        if (variance != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              variance.isZero
                  ? 'Kas sesuai.'
                  : variance.isNegative
                      ? 'Kurang ${ref.money(-variance)}'
                      : 'Lebih ${ref.money(variance)}',
              key: const Key('shift-variance'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: variance.isNegative ? Theme.of(context).colorScheme.error : null,
              ),
            ),
          ),
        const SizedBox(height: 12),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Catatan (opsional)')),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('shift-close-submit'),
          onPressed: busy || counted == null
              ? null
              : () => submit(
                    () async {
                      await ref.read(shiftControllerProvider.notifier).close(closingRupiah: counted, notes: _notes.text);
                    },
                    success: 'Shift ditutup.',
                  ),
          child: Text(busy ? 'Memproses...' : 'TUTUP SHIFT'),
        ),
      ],
    );
  }
}
