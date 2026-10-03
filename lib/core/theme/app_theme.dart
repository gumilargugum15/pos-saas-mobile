import 'package:flutter/material.dart';

/// Kagoem POS brand: the web app's `--primary` (oklch(0.556 0.223 262)).
abstract final class BrandColors {
  static const primary = Color(0xFF2563EB);
  static const primaryDark = Color(0xFF6E8EF7);
  static const success = Color(0xFF15803D);
  static const warning = Color(0xFFB45309);
}

/// Material 3 themes tuned for a cashier: high contrast, large touch
/// targets (≥ 48dp, primary actions 56dp), few decorations.
abstract final class AppTheme {
  static ThemeData get light => _build(
        ColorScheme.fromSeed(
          seedColor: BrandColors.primary,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
          contrastLevel: 0.5,
        ),
      );

  static ThemeData get dark => _build(
        ColorScheme.fromSeed(
          seedColor: BrandColors.primaryDark,
          brightness: Brightness.dark,
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
          contrastLevel: 0.5,
        ),
      );

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    const radius = BorderRadius.all(Radius.circular(12));

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      textTheme: base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 56),
          shape: const RoundedRectangleBorder(borderRadius: radius),
          textStyle: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: const RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: scheme.outline),
          textStyle: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: const OutlineInputBorder(borderRadius: radius),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outline)),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 12),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
