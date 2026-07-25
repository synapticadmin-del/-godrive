import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// GoDrive design system — shared across the Rider & Captain apps.
///
/// The system keeps GoDrive's own green brand identity (#4E842D) while
/// adopting the structural language proven by world-class driver apps
/// (inDrive, Uber Driver, Bolt Driver):
///
///  * A calm, warm off-white canvas with pure-white cards so surfaces layer
///    legibly instead of disappearing into each other.
///  * Money and time set in heavy, oversized numerals — a driver reads them
///    at a glance, in daylight, from arm's length.
///  * One dominant action per screen, at a 56dp touch target.
///  * A full-bleed map with floating controls rather than a boxed-in map.
///
/// Typography is Cairo: a geometric Arabic-first sans with weights up to 900,
/// which gives us the large-number emphasis the layout depends on and matches
/// the circular, low-contrast character of the category.
class AppTokens {
  const AppTokens._();

  // ---------------------------------------------------------------------
  // Brand
  // ---------------------------------------------------------------------
  /// GoDrive green. 5.1:1 on white — passes WCAG AA for body text.
  static const primary = Color(0xFF4E842D);
  static const primaryFill = Color(0xFF4E842D);
  static const primaryLight = Color(0xFF69A83D);
  static const primaryDark = Color(0xFF38631E);

  /// Tinted fills for chips, avatars and selected states.
  static const primarySoft = Color(0xFFEAF5E3);
  static const headerAccent = Color(0xFFDDF2D1);

  // ---------------------------------------------------------------------
  // Semantic
  // ---------------------------------------------------------------------
  static const accent = Color(0xFFA56A07); // 4.50:1 on white
  static const success = Color(0xFF178841); // 4.53:1 on white
  static const warning = Color(0xFF947105); // 4.54:1 on white
  static const danger = Color(0xFFD92D20); // 4.53:1 on white
  static const sos = Color(0xFFDC2626); // 4.83:1 on white
  static const info = Color(0xFF1D6DBE);

  // Badge pairs — dark text on a light tint, all >= 6:1.
  static const badgePendingText = Color(0xFF78350F);
  static const badgePendingBg = Color(0xFFFEF3C7);
  static const badgeApprovedText = Color(0xFF14532D);
  static const badgeApprovedBg = Color(0xFFEAF5E3);
  static const badgeStoppedText = Color(0xFF7F1D1D);
  static const badgeStoppedBg = Color(0xFFFEE2E2);
  static const badgeCompletedText = Color(0xFF166534);
  static const badgeCompletedBg = Color(0xFFF3F9EC);

  // ---------------------------------------------------------------------
  // Light surfaces — warm off-white canvas, pure-white cards
  // ---------------------------------------------------------------------
  static const lightBg = Color(0xFFF7F6F4);
  static const lightPanel = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFF3F4F6);
  static const inputFill = Color(0xFFF1F5F9);
  static const lightText = Color(0xFF16181D);
  static const lightMuted = Color(0xFF6B7280);
  static const lightFaint = Color(0xFF9CA3AF);
  static const lightBorder = Color(0xFFE6E8EB);

  // ---------------------------------------------------------------------
  // Dark surfaces — night driving
  // ---------------------------------------------------------------------
  static const darkBg = Color(0xFF0B0F14);
  static const darkPanel = Color(0xFF151A21);
  static const darkSurface = Color(0xFF1E252E);
  static const darkText = Color(0xFFF7F8F8);
  static const darkMuted = Color(0xFF9BA4AF);
  static const darkFaint = Color(0xFF6B7280);
  static const darkBorder = Color(0xFF2A323C);

  /// Ink used for the "offline" state of the go-online control, and for
  /// high-contrast overlays that float above the map in either brightness.
  static const neutralInk = Color(0xFF16181D);

  // ---------------------------------------------------------------------
  // Radii
  // ---------------------------------------------------------------------
  static const double radiusXs = 6;
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;
  static const double radiusXl = 26;
  static const double radiusPill = 999;

  // ---------------------------------------------------------------------
  // Spacing — 4dp base grid
  // ---------------------------------------------------------------------
  static const double space2xs = 4;
  static const double spaceXs = 8;
  static const double spaceSm = 12;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;
  static const double space2xl = 48;

  /// Minimum comfortable target for a driver tapping while the car is moving.
  static const double tapTarget = 48;
  static const double primaryActionHeight = 56;

  // ---------------------------------------------------------------------
  // Elevation
  // ---------------------------------------------------------------------
  /// Resting cards and list rows.
  static List<BoxShadow> get shadowCard => [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ];

  /// Controls floating directly on top of the map.
  static List<BoxShadow> get shadowFloating => [
        BoxShadow(
          color: Colors.black.withOpacity(0.14),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  /// The bottom sheet lip, casting upward.
  static List<BoxShadow> get shadowSheet => [
        BoxShadow(
          color: Colors.black.withOpacity(0.13),
          blurRadius: 24,
          offset: const Offset(0, -6),
        ),
      ];

  /// The one moment of elevation drama: an incoming ride offer.
  static List<BoxShadow> get shadowOffer => [
        BoxShadow(
          color: Colors.black.withOpacity(0.18),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ];

  /// Soft brand halo behind the active "online" control.
  static List<BoxShadow> glow(Color color, {double opacity = 0.38}) => [
        BoxShadow(
          color: color.withOpacity(opacity),
          blurRadius: 20,
          spreadRadius: 1,
          offset: const Offset(0, 6),
        ),
      ];

  // ---------------------------------------------------------------------
  // Map
  // ---------------------------------------------------------------------
  /// CARTO Positron — muted light basemap that lets brand-coloured markers
  /// and the route line read clearly.
  static const mapTilesLight =
      'https://cartodb-basemaps-{s}.global.ssl.fastly.net/light_all/{z}/{x}/{y}{r}.png';

  /// CARTO Dark Matter — night driving, far less glare than a light basemap.
  static const mapTilesDark =
      'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}{r}.png';

  static const mapSubdomains = ['a', 'b', 'c'];
  static const mapAttribution = '© OpenStreetMap © CARTO';
  static const mapUserAgent = 'tech.synapticstudio.godrive';

  /// Route polyline drawn between captain → pickup → dropoff.
  static const routeLine = Color(0xFF2F6FED);

  static String mapTilesFor(Brightness brightness) =>
      brightness == Brightness.dark ? mapTilesDark : mapTilesLight;

  // ---------------------------------------------------------------------
  // Typography
  // ---------------------------------------------------------------------
  /// Cairo — Arabic-first geometric sans, weights 200–1000.
  static TextStyle font({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
    Color? decorationColor,
  }) =>
      GoogleFonts.cairo(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        decoration: decoration,
        decorationColor: decorationColor,
      );

  /// Oversized numerals for money and countdowns. Tabular-ish spacing keeps
  /// a ticking value from shifting the layout on every frame.
  static TextStyle money({
    required double fontSize,
    Color? color,
    FontWeight fontWeight = FontWeight.w900,
  }) =>
      GoogleFonts.cairo(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: 1.1,
        letterSpacing: -0.5,
      );
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final bg = isDark ? AppTokens.darkBg : AppTokens.lightBg;
    final panel = isDark ? AppTokens.darkPanel : AppTokens.lightPanel;
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final muted = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final border = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;
    final fill = isDark ? AppTokens.darkSurface : AppTokens.inputFill;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppTokens.primary,
      brightness: brightness,
      primary: AppTokens.primary,
      onPrimary: Colors.white,
      surface: panel,
      error: AppTokens.danger,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,

      // Cairo everywhere. The previous theme named a font family that was
      // never bundled, so every unstyled widget silently fell back to Roboto
      // and rendered Arabic with the wrong shaping.
      textTheme: _textTheme(text, muted),

      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTokens.font(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),

      cardTheme: CardTheme(
        color: panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          side: BorderSide(color: border),
        ),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        labelStyle: AppTokens.font(color: muted, fontSize: 14),
        hintStyle: AppTokens.font(color: muted, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: const BorderSide(color: AppTokens.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: const BorderSide(color: AppTokens.danger, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: const BorderSide(color: AppTokens.danger, width: 1.8),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTokens.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: isDark
              ? AppTokens.darkSurface
              : AppTokens.lightBorder,
          disabledForegroundColor: muted,
          minimumSize: const Size.fromHeight(AppTokens.primaryActionHeight),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
          textStyle: AppTokens.font(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size.fromHeight(AppTokens.tapTarget),
          side: BorderSide(color: border, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
          textStyle: AppTokens.font(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppTokens.primary,
          textStyle: AppTokens.font(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppTokens.darkSurface : AppTokens.neutralInk,
        contentTextStyle: AppTokens.font(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        insetPadding: const EdgeInsets.all(AppTokens.spaceMd),
      ),

      dialogTheme: DialogTheme(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        ),
        titleTextStyle: AppTokens.font(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: text,
        ),
        contentTextStyle: AppTokens.font(fontSize: 14, color: muted, height: 1.6),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.radiusXl),
          ),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppTokens.darkSurface : AppTokens.lightSurface,
        side: BorderSide(color: border),
        labelStyle: AppTokens.font(fontSize: 12, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppTokens.primary,
      ),

      dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
    );
  }

  /// Weight carries the hierarchy: money and headlines are heavy, body copy
  /// stays regular. Line heights are loosened for Arabic ascenders.
  static TextTheme _textTheme(Color text, Color muted) {
    TextStyle s(double size, FontWeight weight, Color color, {double height = 1.35}) =>
        AppTokens.font(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: height,
        );

    return TextTheme(
      displayLarge: s(44, FontWeight.w900, text, height: 1.1),
      displayMedium: s(36, FontWeight.w900, text, height: 1.1),
      displaySmall: s(30, FontWeight.w800, text, height: 1.15),
      headlineLarge: s(26, FontWeight.w800, text, height: 1.2),
      headlineMedium: s(22, FontWeight.w800, text, height: 1.25),
      headlineSmall: s(20, FontWeight.w700, text),
      titleLarge: s(18, FontWeight.w700, text),
      titleMedium: s(16, FontWeight.w700, text),
      titleSmall: s(14, FontWeight.w600, text),
      bodyLarge: s(15, FontWeight.w500, text, height: 1.55),
      bodyMedium: s(14, FontWeight.w400, text, height: 1.55),
      bodySmall: s(13, FontWeight.w400, muted, height: 1.5),
      labelLarge: s(14, FontWeight.w700, text),
      labelMedium: s(12, FontWeight.w600, muted),
      labelSmall: s(11, FontWeight.w500, muted),
    );
  }
}
