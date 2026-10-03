import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/feedback.dart';
import '../../../data/repositories/sales_repository_impl.dart';
import '../../../domain/entities/party.dart';
import '../../auth/application/session_controller.dart';
import '../customer_providers.dart';

/// Result of the picker: [CustomerChoice.walkIn] or a customer.
class CustomerChoice {
  const CustomerChoice(this.customer);

  static const walkIn = CustomerChoice(null);

  final Customer? customer;
}

Future<CustomerChoice?> showCustomerPicker(BuildContext context) {
  return showModalBottomSheet<CustomerChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const FractionallySizedBox(heightFactor: 0.85, child: _CustomerPicker()),
  );
}

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _term = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final created = await showCreateCustomerSheet(context, initialName: _term);
    if (created != null && mounted) Navigator.pop(context, CustomerChoice(created));
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(customerSearchProvider(_term));
    final canCreate = ref.watch(cashierCapabilitiesProvider)?.canCreateCustomer ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _search,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Cari nama, telepon, atau email', prefixIcon: Icon(Icons.search)),
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _term = value.trim()));
            },
          ),
        ),
        ListTile(
          key: const Key('customer-walk-in'),
          leading: const CircleAvatar(child: Icon(Icons.directions_walk)),
          title: const Text('Walk-in (tanpa pelanggan)', style: TextStyle(fontWeight: FontWeight.w700)),
          onTap: () => Navigator.pop(context, CustomerChoice.walkIn),
        ),
        if (canCreate)
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_add_alt)),
            title: const Text('Tambah pelanggan baru'),
            onTap: _create,
          ),
        const Divider(height: 1),
        Expanded(
          child: results.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => StatusView(
              icon: Icons.cloud_off,
              message: e is AppFailure ? e.message : 'Gagal memuat pelanggan.',
              actionLabel: 'Coba Lagi',
              onAction: () => ref.invalidate(customerSearchProvider(_term)),
            ),
            data: (customers) => customers.isEmpty
                ? StatusView(
                    icon: Icons.person_search,
                    message: _term.isEmpty ? 'Belum ada pelanggan.' : 'Pelanggan "$_term" tidak ditemukan.',
                  )
                : ListView.builder(
                    itemCount: customers.length,
                    itemBuilder: (context, i) {
                      final c = customers[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase())),
                        title: Text(c.name),
                        subtitle: Text([c.phone, c.email].whereType<String>().join(' · ')),
                        onTap: () => Navigator.pop(context, CustomerChoice(c)),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

/// New customer form (`POST /customers`, needs `manage-customers`).
Future<Customer?> showCreateCustomerSheet(BuildContext context, {String initialName = ''}) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _CreateCustomerForm(initialName: initialName),
  );
}

class _CreateCustomerForm extends ConsumerStatefulWidget {
  const _CreateCustomerForm({required this.initialName});

  final String initialName;

  @override
  ConsumerState<_CreateCustomerForm> createState() => _CreateCustomerFormState();
}

class _CreateCustomerFormState extends ConsumerState<_CreateCustomerForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _saving = false;
  AppFailure? _failure;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final customer = await ref.read(salesRepositoryProvider).createCustomer(
            name: _name.text,
            phone: _phone.text,
            email: _email.text,
          );
      if (!mounted) return;
      showQuickMessage(context, 'Pelanggan ${customer.name} ditambahkan.');
      Navigator.pop(context, customer);
    } on AppFailure catch (failure) {
      if (mounted) setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pelanggan Baru', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            if (_failure != null) ...[MessageBanner(_failure!.message), const SizedBox(height: 12)],
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nama *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Nama wajib diisi.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: 'Telepon', errorText: _failure?.fieldError('phone') != null ? _failure!.message : null),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                errorText: _failure?.fieldError('email') != null ? 'Email tidak valid atau sudah dipakai.' : null,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Menyimpan...' : 'SIMPAN'),
            ),
          ],
        ),
      ),
    );
  }
}
