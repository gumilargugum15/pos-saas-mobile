import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_failure.dart';
import '../../auth/application/session_controller.dart';

/// Opens the tenant picker; a failure to load memberships stays on the
/// current screen with a message.
Future<void> switchTenantOrNotify(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(sessionControllerProvider.notifier).switchTenant();
  } on AppFailure catch (failure) {
    messenger.showSnackBar(SnackBar(content: Text(failure.message)));
  }
}
