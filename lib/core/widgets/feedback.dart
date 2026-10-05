import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// App-wide messenger, so messages can be cleared from outside a widget.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Clears transient messages when a new screen opens: a message from the
/// previous screen must never sit on top of the next screen's buttons
/// (e.g. "added to cart" covering CHECKOUT right after opening the cart).
///
/// Not on pop: a result message shown while closing a screen ("Produk
/// diperbarui", "Pelanggan ditambahkan") belongs to the screen underneath.
class ClearMessagesOnNavigation extends NavigatorObserver {
  void _clear() => rootMessengerKey.currentState?.hideCurrentSnackBar();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _clear();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _clear();
}

/// Short, non-blocking feedback for fast cashier actions: replaces the
/// previous message instead of queueing behind it.
void showQuickMessage(BuildContext context, String message, {bool isError = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final scheme = Theme.of(context).colorScheme;
  if (isError) {
    HapticFeedback.heavyImpact();
  } else {
    HapticFeedback.selectionClick();
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(milliseconds: isError ? 2500 : 1200),
        backgroundColor: isError ? scheme.error : null,
      ),
    );
}

/// Loading / error / empty placeholders used by list screens.
class StatusView extends StatelessWidget {
  const StatusView({super.key, required this.icon, required this.message, this.actionLabel, this.onAction});

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
