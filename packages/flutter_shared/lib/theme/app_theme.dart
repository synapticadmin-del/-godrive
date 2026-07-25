import 'package:flutter/material.dart';

/// Design tokens shared across Rider & Captain apps, aligned with the
/// GoDrive brand identity (Light White & GoDrive Green Theme):
///  - Primary: GoDrive Green #72BF44 (fresh, natural)
///  - Primary Dark: #5E9E37
///  - Primary Light: #EAF5E3
///  - Accent Header: #DDF2D1
///  - Pure White Light Theme & Clean Light Cards
class AppTokens {
  // Brand — GoDrive Green (#72BF44 family from screenshots)
  static const primary = Color(0xFF72BF44);
  static const primaryDark = Color(0xFF5E9E37);
  static const primaryLight = Color(0xFFEAF5E3);
  static const headerAccent = Color(0xFFDDF2D1);
  static const accent = Color(0xFFF59E0B);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFEAB308);
  static const danger = Color(0xFFEF4444);
  static const sos = Color(0xFFDC2626);

  // Light — Pure White & Soft Slate
  static const lightBg = Color(0xFFFFFFFF);
  static const lightPanel = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFF8FAFC);
  static const inputFill = Color(0xFFF1F5F9);
  static const lightText = Color(0xFF0F172A);
  static const lightMuted = Color(0xFF64748B);
  static const lightBorder = Color(0xFFE2E8F0);

  // Dark fallback
  static const darkBg = Color(0xFF0B1220);
  static const darkPanel = Color(0xFF121A2B);
  static const darkSurface = Color(0xFF1E293B);
  static const darkText = Color(0xFFFAFAFA);
  static const darkMuted = Color(0xFFA3A3A3);
  static const darkBorder = Color(0xFF334155);

  // Radii
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;

  // Typography
  static const String arabicFontFamily = 'IBM Plex Sans Arabic';
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppTokens.primary,
      brightness: brightness,
      primary: AppTokens.primary,
      background: isDark ? AppTokens.darkBg : AppTokens.lightBg,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? AppTokens.darkBg : AppTokens.lightBg,
      fontFamily: AppTokens.arabicFontFamily,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppTokens.darkPanel : AppTokens.lightPanel,
        foregroundColor: isDark ? AppTokens.darkText : AppTokens.lightText,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardTheme(
        color: isDark ? AppTokens.darkPanel : AppTokens.lightPanel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          side: BorderSide(color: isDark ? AppTokens.darkBorder : AppTokens.lightBorder, width: 0.8),
        ),
        elevation: 1,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppTokens.darkSurface : AppTokens.inputFill,
        labelStyle: TextStyle(color: isDark ? AppTokens.darkMuted : AppTokens.lightMuted, fontSize: 14),
        hintStyle: TextStyle(color: isDark ? AppTokens.darkMuted : AppTokens.lightMuted, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: const BorderSide(color: AppTokens.primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTokens.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: AppTokens.arabicFontFamily),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? AppTokens.darkBorder : AppTokens.lightBorder,
        space: 1,
      ),
    );
  }
}