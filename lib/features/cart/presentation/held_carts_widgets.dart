import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/feedback.dart';
import '../../../domain/entities/held_cart.dart';
import '../../settings/settings_providers.dart';
import '../application/cart_controller.dart';
import '../application/held_carts_controller.dart';

final _time = DateFormat('HH:mm');
final _dayTime = DateFormat('dd/MM HH:mm');

/// App-bar action: held carts with a count badge (web "Held").
class HeldCartsButton extends ConsumerWidget {
  const HeldCartsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(heldCartsControllerProvider).value?.length ?? 0;
    return IconButton(
      key: const Key('held-open'),
      tooltip: 'Transaksi ditahan',
      onPressed: () => showHeldCartsSheet(context),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.pause_circle_outline),
      ),
    );
  }
}

/// "TAHAN": park the cart with an optional note, then serve the next
/// customer.
Future<void> holdCurrentCart(BuildContext context, WidgetRef ref) async {
  final note = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _HoldSheet(),
  );
  if (note == null || !context.mounted) return;
  try {
    final held = await ref.read(heldCartsControllerProvider.notifier).hold(note: note);
    if (context.mounted) showQuickMessage(context, 'Transaksi "${held.label}" ditahan.');
  } on HoldException catch (e) {
    if (context.mounted) showQuickMessage(context, e.message, isError: true);
  }
}

class _HoldSheet extends ConsumerStatefulWidget {
  const _HoldSheet();

  @override
  ConsumerState<_HoldSheet> createState() => _HoldSheetState();
}

class _HoldSheetState extends ConsumerState<_HoldSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Tahan Transaksi', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${cart.itemCount} item · ${ref.money(cart.grandTotal)}. Lanjutkan kapan saja dari tombol "Ditahan".'),
          const SizedBox(height: 16),
          TextField(
            key: const Key('hold-note'),
            controller: _note,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Catatan (opsional)',
              hintText: 'mis. Meja 3, Bapak baju merah',
            ),
            onSubmitted: (_) => Navigator.pop(context, _note.text),
          ),
          FilledButton.icon(
            key: const Key('hold-confirm'),
            onPressed: () => Navigator.pop(context, _note.text),
            icon: const Icon(Icons.pause),
            label: const Text('TAHAN'),
          ),
        ],
      ),
    );
  }
}

Future<void> showHeldCartsSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const FractionallySizedBox(heightFactor: 0.8, child: _HeldCartsSheet()),
    );

class _HeldCartsSheet extends ConsumerStatefulWidget {
  const _HeldCartsSheet();

  @override
  ConsumerState<_HeldCartsSheet> createState() => _HeldCartsSheetState();
}

class _HeldCartsSheetState extends ConsumerState<_HeldCartsSheet> {
  String? _busyId;

  Future<void> _resume(HeldCart held) async {
    if (_busyId != null) return;
    setState(() => _busyId = held.id);
    final navigator = Navigator.of(context);
    try {
      final report = await ref.read(heldCartsControllerProvider.notifier).resume(held.id);
      navigator.pop();
      if (!mounted) return;
      if (report.hasChanges) {
        await _showChanges(navigator.context, held, report);
      } else if (navigator.context.mounted) {
        showQuickMessage(navigator.context, 'Transaksi "${held.label}" dilanjutkan.');
      }
    } on HoldException catch (e) {
      if (mounted) showQuickMessage(context, e.message, isError: true);
    } on AppFailure catch (f) {
      if (mounted) showQuickMessage(context, 'Gagal memeriksa produk: ${f.message}', isError: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _discard(HeldCart held) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus transaksi ditahan?'),
        content: Text('"${held.label}" (${held.itemCount} item) akan dihapus dari perangkat ini.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok ?? false) await ref.read(heldCartsControllerProvider.notifier).discard(held.id);
  }

  @override
  Widget build(BuildContext context) {
    final held = ref.watch(heldCartsControllerProvider);
    final cartHasItems = ref.watch(cartControllerProvider.select((c) => c.isNotEmpty));
    final textTheme = Theme.of(context).textTheme;
    final today = DateUtils.dateOnly(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Transaksi Ditahan', style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ),
        if (cartHasItems)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: MessageBanner(
              'Keranjang saat ini akan ikut ditahan saat Anda melanjutkan transaksi lain.',
              tone: BannerTone.info,
            ),
          ),
        Expanded(
          child: held.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const StatusView(icon: Icons.error_outline, message: 'Daftar tidak dapat dimuat.'),
            data: (list) => list.isEmpty
                ? const StatusView(
                    icon: Icons.pause_circle_outline,
                    message: 'Belum ada transaksi yang ditahan.\nGunakan tombol TAHAN di keranjang.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final h = list[i];
                      final when = DateUtils.dateOnly(h.createdAt) == today ? _time : _dayTime;
                      final busy = _busyId == h.id;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(h.label, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                    Text(
                                      [
                                        '${h.itemCount} item',
                                        when.format(h.createdAt),
                                        if (h.note != null && h.customer != null) h.customer!.name,
                                      ].join(' · '),
                                      style: textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      ref.money(h.estimatedTotal),
                                      style: textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Hapus',
                                onPressed: _busyId == null ? () => _discard(h) : null,
                                icon: const Icon(Icons.delete_outline),
                              ),
                              FilledButton(
                                key: Key('held-resume-${h.id}'),
                                onPressed: _busyId == null ? () => _resume(h) : null,
                                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                                child: busy
                                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Text('LANJUTKAN'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

Future<void> _showChanges(BuildContext context, HeldCart held, ResumeReport report) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Ada perubahan sejak ditahan'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Transaksi "${held.label}" dilanjutkan dengan data terbaru:'),
          const SizedBox(height: 8),
          for (final n in report.notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [const Text('•  '), Expanded(child: Text(n))],
              ),
            ),
        ],
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    ),
  );
}
