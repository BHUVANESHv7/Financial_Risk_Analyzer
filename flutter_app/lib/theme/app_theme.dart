import 'package:flutter/material.dart';

/// Semantic colours that adapt to light/dark mode.
/// Access with `context.palette`.
@immutable
class Palette extends ThemeExtension<Palette> {
  final Color success, successBg;
  final Color warning, warningBg;
  final Color danger, dangerBg;
  final Color info, infoBg;
  final Color muted;
  final Color border;
  final Color surfaceAlt;

  const Palette({
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.danger,
    required this.dangerBg,
    required this.info,
    required this.infoBg,
    required this.muted,
    required this.border,
    required this.surfaceAlt,
  });

  static const light = Palette(
    success: Color(0xFF047857),
    successBg: Color(0xFFD1FAE5),
    warning: Color(0xFFB45309),
    warningBg: Color(0xFFFEF3C7),
    danger: Color(0xFFB91C1C),
    dangerBg: Color(0xFFFEE2E2),
    info: Color(0xFF1D4ED8),
    infoBg: Color(0xFFDBEAFE),
    muted: Color(0xFF64748B),
    border: Color(0xFFE2E8F0),
    surfaceAlt: Color(0xFFF1F5F9),
  );

  static const dark = Palette(
    success: Color(0xFF34D399),
    successBg: Color(0xFF064E3B),
    warning: Color(0xFFFBBF24),
    warningBg: Color(0xFF4A3410),
    danger: Color(0xFFF87171),
    dangerBg: Color(0xFF4C1D1D),
    info: Color(0xFF60A5FA),
    infoBg: Color(0xFF1E3A5F),
    muted: Color(0xFF94A3B8),
    border: Color(0xFF334155),
    surfaceAlt: Color(0xFF1E293B),
  );

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) =>
      (other is Palette && t > 0.5) ? other : this;
}

extension PaletteX on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

class AppTheme {
  static const brand = Color(0xFF1A56DB);
  static const brandAccent = Color(0xFF0E9F6E);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isDark = b == Brightness.dark;
    final palette = isDark ? Palette.dark : Palette.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: b,
      surface: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
    ).copyWith(
      primary: isDark ? const Color(0xFF60A5FA) : brand,
      onPrimary: isDark ? const Color(0xFF0B1220) : Colors.white,
      surfaceContainerLowest: isDark ? const Color(0xFF111A2E) : Colors.white,
      surfaceContainerLow: isDark ? const Color(0xFF16213A) : Colors.white,
    );
    final radius = BorderRadius.circular(14);

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [palette],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: palette.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: palette.border),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide(color: palette.border),
      ),
      dividerTheme: DividerThemeData(color: palette.border, space: 1),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
