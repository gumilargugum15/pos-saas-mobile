import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/party.dart';
import 'outlet_controller.dart';

Future<void> showOutletPicker(BuildContext context, WidgetRef ref, OutletState outlet) async {
  final branch = await showModalBottomSheet<Branch>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final b in outlet.options)
            ListTile(
              leading: Icon(b == outlet.selected ? Icons.radio_button_checked : Icons.radio_button_off),
              title: Text(b.name),
              subtitle: b.address == null ? null : Text(b.address!),
              onTap: () => Navigator.pop(context, b),
            ),
        ],
      ),
    ),
  );
  if (branch != null) await ref.read(outletControllerProvider.notifier).select(branch);
}
