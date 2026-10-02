import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/widgets/feedback.dart';
import '../../auth/application/session_controller.dart';
import '../customer_providers.dart';
import 'customer_widgets.dart';

/// Look up customers; add one when the backend permission allows it.
/// No CRM features (edit, delete, history) on purpose.
class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  Timer? _debounce;
  String _term = '';

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(customerSearchProvider(_term));
    final canCreate = ref.watch(cashierCapabilitiesProvider)?.canCreateCustomer ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Pelanggan')),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () async {
                final created = await showCreateCustomerSheet(context, initialName: _term);
                if (created != null) ref.invalidate(customerSearchProvider);
              },
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Tambah'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(hintText: 'Cari nama, telepon, atau email', prefixIcon: Icon(Icons.search)),
                onChanged: (value) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _term = value.trim()));
                },
              ),
            ),
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
                    : ListView.separated(
                        itemCount: customers.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final c = customers[i];
                          return ListTile(
                            leading: CircleAvatar(child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase())),
                            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text([c.phone, c.email].whereType<String>().join(' · ')),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
