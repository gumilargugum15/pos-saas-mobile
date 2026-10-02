import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../cart/application/cart_controller.dart';
import '../../pos/application/scan_to_cart.dart';
import '../../settings/settings_providers.dart';

/// Camera scanner in continuous mode: every recognised code goes straight
/// into the cart, and the camera stays open for the next item.
///
/// Flow: scan → exact barcode/SKU lookup → found: add to cart /
/// not found: "Produk tidak ditemukan". Products are never created here.
class ScannerPage extends ConsumerStatefulWidget {
  const ScannerPage({super.key});

  /// EAN-13, EAN-8, UPC-A/E, Code 128, Code 39 and QR.
  static const formats = [
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.qrCode,
  ];

  /// The same code held in front of the camera is read many times per
  /// second; it only counts again after this pause.
  static const repeatGuard = Duration(milliseconds: 1500);

  @override
  ConsumerState<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends ConsumerState<ScannerPage> {
  final _controller = MobileScannerController(
    formats: ScannerPage.formats,
    detectionSpeed: DetectionSpeed.normal,
  );

  bool _busy = false;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  ScanOutcome? _outcome;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final code = capture.barcodes.map((b) => b.rawValue?.trim()).whereType<String>().where((c) => c.isNotEmpty).firstOrNull;
    if (code == null || _busy) return;

    final now = DateTime.now();
    if (code == _lastCode && now.difference(_lastAt) < ScannerPage.repeatGuard) return;
    _lastCode = code;
    _lastAt = now;

    setState(() => _busy = true);
    final outcome = await ref.read(scanToCartProvider)(code);
    if (!mounted) return;
    outcome.isSuccess ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();
    setState(() {
      _busy = false;
      _outcome = outcome;
      _lastAt = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        actions: [
          IconButton(
            tooltip: 'Senter',
            onPressed: _controller.toggleTorch,
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (_, state, _) => Icon(state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off),
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(error: error),
          ),
          const _ScanFrame(),
          if (_busy) const Center(child: CircularProgressIndicator()),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_outcome != null) _OutcomeBanner(outcome: _outcome!),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
                      child: Text(
                        cart.isEmpty
                            ? 'SELESAI'
                            : 'SELESAI · ${cart.itemCount} item · ${ref.money(cart.grandTotal)}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutcomeBanner extends StatelessWidget {
  const _OutcomeBanner({required this.outcome});

  final ScanOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = outcome.isSuccess;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ok ? Colors.green.shade700 : scheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(ok ? Icons.check_circle : Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                outcome.message,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 280,
          height: 180,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 3),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'Izin kamera ditolak. Aktifkan izin kamera untuk Kagoem POS di Pengaturan perangkat.',
      MobileScannerErrorCode.unsupported => 'Perangkat ini tidak mendukung pemindaian kamera.',
      _ => 'Kamera tidak dapat dibuka. Tutup aplikasi lain yang memakai kamera lalu coba lagi.',
    };
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography, color: Colors.white, size: 56),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 8),
              const Text(
                'Anda tetap bisa mengetik barcode di kolom pencarian.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
