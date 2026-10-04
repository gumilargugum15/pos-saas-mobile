import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The Kagoem mark (frontend/public/logo-mark.svg): gradient rounded
/// square, white "K", light-blue dot. Drawn from the SVG's 40×40 geometry.
class KagoemLogoMark extends StatelessWidget {
  const KagoemLogoMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 9 / 40),
          // Web "shadow-brand".
          boxShadow: [
            BoxShadow(
              color: KagoemTokens.primary.withValues(alpha: 0.28),
              blurRadius: size * 0.6,
              offset: Offset(0, size * 0.2),
            ),
          ],
        ),
        child: CustomPaint(painter: _MarkPainter()),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 40;
    canvas.scale(s);

    const rect = Rect.fromLTWH(0, 0, 40, 40);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(9)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KagoemTokens.logoStart, KagoemTokens.logoEnd],
        ).createShader(rect),
    );

    final k = Path()
      ..moveTo(13, 8.5)
      ..lineTo(17.2, 8.5)
      ..lineTo(17.2, 17.4)
      ..lineTo(26.3, 8.5)
      ..lineTo(31.8, 8.5)
      ..lineTo(21, 20)
      ..lineTo(31.8, 31.5)
      ..lineTo(26.3, 31.5)
      ..lineTo(17.2, 22.6)
      ..lineTo(17.2, 31.5)
      ..lineTo(13, 31.5)
      ..close();
    canvas.drawPath(k, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(30.5, 10.5), 2.1, Paint()..color = KagoemTokens.logoDot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Mark + "Kagoem" + "POS" pill (frontend/public/logo.svg).
class KagoemLogo extends StatelessWidget {
  const KagoemLogo({super.key, this.height = 40, this.showMark = true});

  final double height;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final scale = height / 40;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showMark) ...[
          KagoemLogoMark(size: height),
          SizedBox(width: 12 * scale),
        ],
        Text(
          'Kagoem',
          style: TextStyle(fontSize: 23 * scale, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: onSurface),
        ),
        SizedBox(width: 8 * scale),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 7 * scale, vertical: 2 * scale),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5 * scale),
            gradient: const LinearGradient(colors: [KagoemTokens.logoStart, KagoemTokens.logoEnd]),
          ),
          child: Text(
            'POS',
            style: TextStyle(fontSize: 11 * scale, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
