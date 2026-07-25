import 'package:flutter/material.dart';

/// Design tokens shared across Rider & Captain apps, aligned with the
/// GoDrive brand identity.
///
/// The palette supports BOTH a light and a dark presentation:
///  - Light: pure white surfaces with GoDrive Green #4E842D (WCAG AA on white)
///  - Dark:  near-black surfaces with a lime action colour #C1F11D
///           (black text on lime ≈ 14:1 contrast — very high legibility)
///
/// IMPORTANT: every token that existed before is preserved verbatim so the
/// Captain and Admin apps keep compiling and rendering unchanged. New tokens
/// are additive only.
class AppTokens {
  // Brand — GoDrive Green (#4E842D family for WCAG AA >= 4.5:1 contrast)
  static const primary = Color(0xFF4E842D);      // 4.50:1 on white (WCAG AA)
  static const primaryFill = Color(0xFF4E842D);  // 4.50:1 on white
  static const primaryDark = Color(0xFF38631E);  // 7.10:1 on white
  static const primaryLight = Color(0xFFEAF5E3);
  static const headerAccent = Color(0xFFDDF2D1);
  static const accent = Color(0xFFA56A07);       // 4.50:1 on white (WCAG AA)
  static const success = Color(0xFF178841);      // 4.53:1 on white (WCAG AA)
  static const warning = Color(0xFF947105);      // 4.54:1 on white (WCAG AA)
  static const danger = Color(0xFFEB1616);       // 4.51:1 on white (WCAG AA)
  static const sos = Color(0xFFDC2626);          // 4.83:1 on white (WCAG AA)

  // Badge Status Colors (High Contrast Dark Text on Light BG)
  static const badgePendingText = Color(0xFF78350F);  // 8.15:1 on #FEF3C7
  static const badgePendingBg = Color(0xFFFEF3C7);
  static const badgeApprovedText = Color(0xFF14532D); // 8.10:1 on #EAF5E3
  static const badgeApprovedBg = Color(0xFFEAF5E3);
  static const badgeStoppedText = Color(0xFF7F1D1D);  // 8.20:1 on #FEE2E2
  static const badgeStoppedBg = Color(0xFFFEE2E2);
  static const badgeCompletedText = Color(0xFF166534);// 6.65:1 on #F3F9EC
  static const badgeCompletedBg = Color(0xFFF3F9EC);

  // Light — Pure White & Soft Slate
  static const lightBg = Color(0xFFFFFFFF);
  static const lightPanel = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFF8FAFC);
  static const inputFill = Color(0xFFF1F5F9);
  static const lightText = Color(0xFF0F172A);
  static const lightMuted = Color(0xFF64748B);
  static const lightBorder = Color(0xFFE2E8F0);

  // Dark fallback (legacy slate-blue dark — kept for Captain/Admin apps)
  static const darkBg = Color(0xFF0B1220);
  static const darkPanel = Color(0xFF121A2B);
  static const darkSurface = Color(0xFF1E293B);
  static const darkText = Color(0xFFFAFAFA);
  static const darkMuted = Color(0xFFA3A3A3);
  static const darkBorder = Color(0xFF334155);

  // ── NEW: Neutral near-black dark scale (ride-hailing night surfaces) ──
  // Used by the Rider app so the map stays the visual hero at night.
  static const nightBg = Color(0xFF0E0E10);      // page background
  static const nightPanel = Color(0xFF1A1A1D);   // sheets, cards
  static const nightSurface = Color(0xFF26262B); // inputs, chips
  static const nightElevated = Color(0xFF313138);// pressed / hover
  static const nightText = Color(0xFFF5F5F7);
  static const nightMuted = Color(0xFF9A9AA2);
  static const nightBorder = Color(0xFF34343B);

  // ── NEW: Lime action colour for dark surfaces ──
  // Lime on near-black reads brilliantly; pair ONLY with black foreground.
  static const lime = Color(0xFFC1F11D);
  static const limePressed = Color(0xFFA9D617);
  static const onLime = Color(0xFF101010);

  // ── NEW: Map & route rendering ──
  static const routeLine = Color(0xFF4E842D);      // route on light basemap
  static const routeLineNight = Color(0xFFFFFFFF); // route on dark basemap
  static const routeCasing = Color(0x33000000);    // soft outline under route
  static const pinPickup = Color(0xFF12B76A);      // origin marker
  static const pinDropoff = Color(0xFFEF4444);     // destination marker

  // Radii
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;
  static const double radiusPill = 999; // NEW — fully-rounded buttons

  // Typography
  static const String arabicFontFamily = 'IBM Plex Sans Arabic';
}

/// Semantic, brightness-aware colours.
///
/// Screens should read these instead of branching on
/// `Theme.of(context).brightness` by hand — that pattern was scattered through
/// the Rider app and caused colours to drift between screens.
///
/// ```dart
/// final go = GoTheme.of(context);
/// Container(color: go.panel, child: Text('...', style: TextStyle(color: go.text)));
/// ```
@immutable
class GoTheme extends ThemeExtension<GoTheme> {
  const GoTheme({
    required this.isDark,
    required this.bg,
    required this.panel,
    required this.surface,
    required this.elevated,
    required this.text,
    required this.muted,
    required this.border,
    required this.action,
    required this.onAction,
    required this.actionPressed,
    required this.routeLine,
    required this.routeCasing,
    required this.pinPickup,
    required this.pinDropoff,
    required this.scrim,
  });

  /// True when the dark presentation is active.
  final bool isDark;

  /// Page background — sits behind everything.
  final Color bg;

  /// Cards, bottom sheets, floating panels.
  final Color panel;

  /// Inputs, chips, inset wells.
  final Color surface;

  /// Pressed/hover state above [surface].
  final Color elevated;

  /// Primary body text.
  final Color text;

  /// Secondary / supporting text.
  final Color muted;

  /// Hairline dividers and outlines.
  final Color border;

  /// Primary call-to-action fill.
  final Color action;

  /// Foreground that is guaranteed legible on [action].
  final Color onAction;

  /// Pressed state of [action].
  final Color actionPressed;

  /// Driving-route polyline colour, tuned per basemap.
  final Color routeLine;

  /// Soft casing drawn beneath the route so it reads over busy tiles.
  final Color routeCasing;

  /// Pickup / origin marker.
  final Color pinPickup;

  /// Dropoff / destination marker.
  final Color pinDropoff;

  /// Overlay behind modals.
  final Color scrim;

  /// Convenience accessor. Falls back to the light palette if the extension
  /// is missing so a screen never crashes mid-trip.
  static GoTheme of(BuildContext context) =>
      Theme.of(context).extension<GoTheme>() ?? _light;

  static const GoTheme _light = GoTheme(
    isDark: false,
    bg: AppTokens.lightBg,
    panel: AppTokens.lightPanel,
    surface: AppTokens.inputFill,
    elevated: AppTokens.lightSurface,
    text: AppTokens.lightText,
    muted: AppTokens.lightMuted,
    border: AppTokens.lightBorder,
    action: AppTokens.primary,
    onAction: Colors.white,
    actionPressed: AppTokens.primaryDark,
    routeLine: AppTokens.routeLine,
    routeCasing: AppTokens.routeCasing,
    pinPickup: AppTokens.pinPickup,
    pinDropoff: AppTokens.pinDropoff,
    scrim: Color(0x66000000),
  );

  static const GoTheme _dark = GoTheme(
    isDark: true,
    bg: AppTokens.nightBg,
    panel: AppTokens.nightPanel,
    surface: AppTokens.nightSurface,
    elevated: AppTokens.nightElevated,
    text: AppTokens.nightText,
    muted: AppTokens.nightMuted,
    border: AppTokens.nightBorder,
    action: AppTokens.lime,
    onAction: AppTokens.onLime,
    actionPressed: AppTokens.limePressed,
    routeLine: AppTokens.routeLineNight,
    routeCasing: Color(0x99000000),
    pinPickup: AppTokens.pinPickup,
    pinDropoff: AppTokens.pinDropoff,
    scrim: Color(0xB3000000),
  );

  static GoTheme forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  @override
  GoTheme copyWith({
    bool? isDark,
    Color? bg,
    Color? panel,
    Color? surface,
    Color? elevated,
    Color? text,
    Color? muted,
    Color? border,
    Color? action,
    Color? onAction,
    Color? actionPressed,
    Color? routeLine,
    Color? routeCasing,
    Color? pinPickup,
    Color? pinDropoff,
    Color? scrim,
  }) {
    return GoTheme(
      isDark: isDark ?? this.isDark,
      bg: bg ?? this.bg,
      panel: panel ?? this.panel,
      surface: surface ?? this.surface,
      elevated: elevated ?? this.elevated,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      border: border ?? this.border,
      action: action ?? this.action,
      onAction: onAction ?? this.onAction,
      actionPressed: actionPressed ?? this.actionPressed,
      routeLine: routeLine ?? this.routeLine,
      routeCasing: routeCasing ?? this.routeCasing,
      pinPickup: pinPickup ?? this.pinPickup,
      pinDropoff: pinDropoff ?? this.pinDropoff,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  GoTheme lerp(ThemeExtension<GoTheme>? other, double t) {
    if (other is! GoTheme) return this;
    return GoTheme(
      isDark: t < 0.5 ? isDark : other.isDark,
      bg: Color.lerp(bg, other.bg, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      action: Color.lerp(action, other.action, t)!,
      onAction: Color.lerp(onAction, other.onAction, t)!,
      actionPressed: Color.lerp(actionPressed, other.actionPressed, t)!,
      routeLine: Color.lerp(routeLine, other.routeLine, t)!,
      routeCasing: Color.lerp(routeCasing, other.routeCasing, t)!,
      pinPickup: Color.lerp(pinPickup, other.pinPickup, t)!,
      pinDropoff: Color.lerp(pinDropoff, other.pinDropoff, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

/// Basemap tile URLs, matched to the active brightness.
///
/// Centralised here so every map in the app (home, saved places, live trip)
/// renders the same cartography instead of each screen hardcoding a URL.
class MapTiles {
  const MapTiles._();

  static const String _light =
      'https://cartodb-basemaps-{s}.global.ssl.fastly.net/light_all/{z}/{x}/{y}{r}.png';
  static const String _dark =
      'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}{r}.png';

  static const List<String> subdomains = ['a', 'b', 'c'];

  /// Required by the CARTO / OpenStreetMap terms of use.
  static const String attribution = '© OpenStreetMap contributors © CARTO';

  static String urlFor(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  static String urlForContext(BuildContext context) =>
      urlFor(Theme.of(context).brightness);
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final go = GoTheme.forBrightness(brightness);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppTokens.primary,
      brightness: brightness,
      primary: go.action,
      onPrimary: go.onAction,
      surface: go.panel,
      onSurface: go.text,
      error: AppTokens.danger,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: go.bg,
      canvasColor: go.bg,
      fontFamily: AppTokens.arabicFontFamily,
      extensions: <ThemeExtension<dynamic>>[go],
      appBarTheme: AppBarTheme(
        backgroundColor: go.bg,
        foregroundColor: go.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardTheme(
        color: go.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          side: BorderSide(color: go.border, width: 0.8),
        ),
        elevation: isDark ? 0 : 1,
        margin: EdgeInsets.zero,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: go.panel,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: go.panel,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTokens.radiusXl),
          ),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: go.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: go.surface,
        labelStyle: TextStyle(color: go.muted, fontSize: 14),
        hintStyle: TextStyle(color: go.muted, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
          borderSide: BorderSide(color: go.action, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: go.action,
          foregroundColor: go.onAction,
          disabledBackgroundColor: go.surface,
          disabledForegroundColor: go.muted,
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            fontFamily: AppTokens.arabicFontFamily,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: go.text,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: go.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            fontFamily: AppTokens.arabicFontFamily,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isDark ? go.action : AppTokens.primary,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: AppTokens.arabicFontFamily,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: go.border, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: go.action),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppTokens.nightElevated : AppTokens.lightText,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontFamily: AppTokens.arabicFontFamily,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: go.muted,
        textColor: go.text,
      ),
      iconTheme: IconThemeData(color: go.text),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: go.panel,
        selectedItemColor: isDark ? go.action : AppTokens.primary,
        unselectedItemColor: go.muted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}
