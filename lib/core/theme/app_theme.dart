import 'package:flutter/material.dart';

/// Design tokens of the Kagoem POS web app (frontend/src/styles.css,
/// "Material 3 + subtle glassmorphism", radius 12px), converted from OKLCH
/// to sRGB so mobile and web look the same.
abstract final class KagoemTokens {
  // Light (:root)
  static const background = Color(0xFFFAFCFE);
  static const foreground = Color(0xFF0A121F);
  static const card = Color(0xFFFFFFFF);
  static const primary = Color(0xFF1E66F3);
  static const primaryForeground = Color(0xFFFAFCFE);
  static const secondary = Color(0xFFEFF4FA);
  static const secondaryForeground = Color(0xFF162235);
  static const muted = Color(0xFFEFF4FA);
  static const mutedForeground = Color(0xFF5D646F);
  static const accent = Color(0xFFE5F1FF);
  static const accentForeground = Color(0xFF11213E);
  static const destructive = Color(0xFFE62B34);
  static const success = Color(0xFF10AE65);
  static const warning = Color(0xFFF6922E);
  static const border = Color(0xFFE0E5EB);
  static const input = Color(0xFFE3E8EE);

  // Dark (.dark)
  static const darkBackground = Color(0xFF080D16);
  static const darkForeground = Color(0xFFF3F5F8);
  static const darkCard = Color(0xFF121824);
  static const darkPrimary = Color(0xFF5893FF);
  static const darkPrimaryForeground = Color(0xFF050B18);
  static const darkSecondary = Color(0xFF192230);
  static const darkMutedForeground = Color(0xFF9DA5B1);
  static const darkAccent = Color(0xFF202E47);
  static const darkDestructive = Color(0xFFF14D4C);
  static const darkSuccess = Color(0xFF43C07A);
  static const darkWarning = Color(0xFFFAAB3F);
  static const darkBorder = Color(0x1AFFFFFF); // white 10%
  static const darkInput = Color(0x24FFFFFF); // white 14%

  /// Logo gradient (public/logo-mark.svg).
  static const logoStart = Color(0xFF2F6BF6);
  static const logoEnd = Color(0xFF1E4FD6);
  static const logoDot = Color(0xFF8FB4FF);

  // --radius: 12px and its Tailwind steps.
  static const radiusMd = 10.0; // buttons, inputs
  static const radiusLg = 12.0;
  static const radiusXl = 16.0; // cards, search, image areas
  static const radius2xl = 20.0; // product cards, cart bar
}

/// Kept for existing call sites; values follow the web tokens.
abstract final class BrandColors {
  static const primary = KagoemTokens.primary;
  static const primaryDark = KagoemTokens.darkPrimary;
  static const success = KagoemTokens.success;
  static const warning = KagoemTokens.warning;
}

/// Material 3 themes matching the web app. Sizes stay touch-friendly for a
/// till (≥ 48dp targets, 52dp buttons), the one deliberate difference from
/// the denser desktop web UI.
abstract final class AppTheme {
  static ThemeData get light => _build(
        const ColorScheme(
          brightness: Brightness.light,
          primary: KagoemTokens.primary,
          onPrimary: KagoemTokens.primaryForeground,
          primaryContainer: KagoemTokens.accent,
          onPrimaryContainer: KagoemTokens.accentForeground,
          secondary: KagoemTokens.secondaryForeground,
          onSecondary: KagoemTokens.card,
          secondaryContainer: KagoemTokens.accent,
          onSecondaryContainer: KagoemTokens.accentForeground,
          tertiary: KagoemTokens.warning,
          onTertiary: Color(0xFF260F00),
          tertiaryContainer: Color(0xFFFFF0E0),
          onTertiaryContainer: Color(0xFF5C2E00),
          error: KagoemTokens.destructive,
          onError: Colors.white,
          errorContainer: Color(0xFFFDE8E9),
          onErrorContainer: Color(0xFF8A1018),
          surface: KagoemTokens.background,
          onSurface: KagoemTokens.foreground,
          onSurfaceVariant: KagoemTokens.mutedForeground,
          surfaceContainerLowest: KagoemTokens.card,
          surfaceContainerLow: KagoemTokens.card,
          surfaceContainer: KagoemTokens.card,
          surfaceContainerHigh: KagoemTokens.secondary,
          surfaceContainerHighest: KagoemTokens.muted,
          outline: Color(0xFFC9D0D9),
          outlineVariant: KagoemTokens.border,
          shadow: Color(0xFF0A1A3A),
          inverseSurface: KagoemTokens.foreground,
          onInverseSurface: KagoemTokens.background,
          inversePrimary: KagoemTokens.darkPrimary,
        ),
        border: KagoemTokens.border,
        input: KagoemTokens.input,
        card: KagoemTokens.card,
      );

  static ThemeData get dark => _build(
        const ColorScheme(
          brightness: Brightness.dark,
          primary: KagoemTokens.darkPrimary,
          onPrimary: KagoemTokens.darkPrimaryForeground,
          primaryContainer: KagoemTokens.darkAccent,
          onPrimaryContainer: KagoemTokens.darkForeground,
          secondary: KagoemTokens.darkForeground,
          onSecondary: KagoemTokens.darkBackground,
          secondaryContainer: KagoemTokens.darkAccent,
          onSecondaryContainer: KagoemTokens.darkForeground,
          tertiary: KagoemTokens.darkWarning,
          onTertiary: Color(0xFF231103),
          tertiaryContainer: Color(0xFF3A2610),
          onTertiaryContainer: KagoemTokens.darkWarning,
          error: KagoemTokens.darkDestructive,
          onError: Colors.white,
          errorContainer: Color(0xFF3B1416),
          onErrorContainer: Color(0xFFFFB3B3),
          surface: KagoemTokens.darkBackground,
          onSurface: KagoemTokens.darkForeground,
          onSurfaceVariant: KagoemTokens.darkMutedForeground,
          surfaceContainerLowest: KagoemTokens.darkBackground,
          surfaceContainerLow: KagoemTokens.darkCard,
          surfaceContainer: KagoemTokens.darkCard,
          surfaceContainerHigh: KagoemTokens.darkSecondary,
          surfaceContainerHighest: KagoemTokens.darkSecondary,
          outline: Color(0x40FFFFFF),
          outlineVariant: KagoemTokens.darkBorder,
          shadow: Colors.black,
          inverseSurface: KagoemTokens.darkForeground,
          onInverseSurface: KagoemTokens.darkBackground,
          inversePrimary: KagoemTokens.primary,
        ),
        border: KagoemTokens.darkBorder,
        input: KagoemTokens.darkInput,
        card: KagoemTokens.darkCard,
      );

  static ThemeData _build(ColorScheme scheme, {required Color border, required Color input, required Color card}) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    const md = BorderRadius.all(Radius.circular(KagoemTokens.radiusMd));
    final textTheme = base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      textTheme: textTheme,
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: border)),
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: scheme.onSurface),
      ),
      // Web "rounded-xl border bg-card shadow-soft".
      cardTheme: CardThemeData(
        elevation: 1,
        margin: EdgeInsets.zero,
        color: card,
        surfaceTintColor: Colors.transparent,
        shadowColor: scheme.shadow.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(KagoemTokens.radiusXl)),
          side: BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: const RoundedRectangleBorder(borderRadius: md),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: const RoundedRectangleBorder(borderRadius: md),
          foregroundColor: scheme.onSurface,
          backgroundColor: card,
          side: BorderSide(color: input),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const RoundedRectangleBorder(borderRadius: md),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(shape: const RoundedRectangleBorder(borderRadius: md)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(borderRadius: md, borderSide: BorderSide(color: input)),
        enabledBorder: OutlineInputBorder(borderRadius: md, borderSide: BorderSide(color: input)),
        focusedBorder: OutlineInputBorder(borderRadius: md, borderSide: BorderSide(color: scheme.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: md, borderSide: BorderSide(color: scheme.error)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: md, borderSide: BorderSide(color: scheme.error, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),
      // Web category pills: "rounded-xl px-3.5 py-1.5 text-xs font-semibold border".
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: scheme.primary,
        disabledColor: scheme.surfaceContainerHighest,
        side: BorderSide(color: border),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(KagoemTokens.radiusLg))),
        labelStyle: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
        secondaryLabelStyle: TextStyle(fontWeight: FontWeight.w600, color: scheme.onPrimary),
        checkmarkColor: scheme.onPrimary,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
          side: BorderSide(color: input),
          shape: const RoundedRectangleBorder(borderRadius: md),
        ),
      ),
      listTileTheme: ListTileThemeData(minVerticalPadding: 12, iconColor: scheme.onSurfaceVariant),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(KagoemTokens.radius2xl))),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(KagoemTokens.radiusLg)),
          side: BorderSide(color: border),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(KagoemTokens.radiusXl))),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w500),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(KagoemTokens.radiusLg))),
      ),
    );
  }
}
