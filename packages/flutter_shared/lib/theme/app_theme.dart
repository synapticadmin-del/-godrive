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
/// The palette supports BOTH a light and a dark presentation:
///  - Light: pure white surfaces with GoDrive Green #4E842D (WCAG AA on white)
///  - Dark:  near-black surfaces with a lime action colour #C1F11D
///           (black text on lime ≈ 14:1 contrast — very high legibility)
///
/// Typography is Cairo: a geometric Arabic-first sans with weights up to 900,
/// which gives us the large-number emphasis the layout depends on and matches
/// the circular, low-contrast character of the category.
///
/// IMPORTANT: every token that existed before is preserved verbatim so the
/// Captain and Admin apps keep compiling and rendering unchanged. New tokens
/// are additive only.
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

  /// Deep forest end-stop for the account header field in dark mode.
  ///
  /// Light mode runs [primary] → [primaryDark]. On a near-black page that
  /// same ramp still reads as a lit panel rather than a surface, so the dark
  /// presentation drops one step further. White on this value is ~11.6:1.
  static const primaryDeep = Color(0xFF22400F);

  // ---------------------------------------------------------------------
  // Semantic
  // ---------------------------------------------------------------------
  static const accent = Color(0xFFA56A07); // 4.50:1 on white
  static const success = Color(0xFF178841); // 4.53:1 on white
  static const warning = Color(0xFF947105); // 4.54:1 on white
  static const danger = Color(0xFFD92D20); // 4.53:1 on white
  static const sos = Color(0xFFDC2626); // 4.83:1 on white
  static const info = Color(0xFF1D6DBE);

  /// Rating stars. Previously an inline hex inside the rider's bids sheet —
  /// tokenised so every star in either app is the same amber.
  static const star = Color(0xFFF5B301);

  /// Full-bleed emergency backdrop — a near-black red that keeps the SOS
  /// screen unmistakable even in peripheral vision, day or night.
  static const sosBackdrop = Color(0xFF1A0000);

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
  static const darkBg = Color(0xFF0B1220);
  static const darkPanel = Color(0xFF121A2B);
  static const darkSurface = Color(0xFF1E293B);
  static const darkText = Color(0xFFFAFAFA);
  static const darkMuted = Color(0xFFA3A3A3);
  static const darkFaint = Color(0xFF6B7280);
  static const darkBorder = Color(0xFF334155);

  /// Ink used for the "offline" state of the go-online control, and for
  /// high-contrast overlays that float above the map in either brightness.
  static const neutralInk = Color(0xFF16181D);

  // ── Neutral near-black dark scale (ride-hailing night surfaces) ──
  // Used by the Rider app so the map stays the visual hero at night.
  static const nightBg = Color(0xFF0E0E10);      // page background
  static const nightPanel = Color(0xFF1A1A1D);   // sheets, cards
  static const nightSurface = Color(0xFF26262B); // inputs, chips
  static const nightElevated = Color(0xFF313138);// pressed / hover
  static const nightText = Color(0xFFF5F5F7);
  static const nightMuted = Color(0xFF9A9AA2);
  static const nightBorder = Color(0xFF34343B);

  // ── Lime action colour for dark surfaces ──
  // Lime on near-black reads brilliantly; pair ONLY with black foreground.
  static const lime = Color(0xFFC1F11D);
  static const limePressed = Color(0xFFA9D617);
  static const onLime = Color(0xFF101010);

  // ── Splash / launch backdrop ──
  // The brand moment before either app hands off to its first themed screen.
  // A near-black field lit by two brand-green sources; referencing these from
  // the token ramp keeps the splash in the design system instead of
  // re-inventing one-off hex per app.
  static const splashBg = Color(0xFF0C1A08);
  static const splashGlowStart = Color(0xFF2C5518);
  static const splashGlowTint = Color(0x333E7A22);
  static const splashFade = Color(0x000C1A08);

  // ── Map & route rendering ──
  static const routeLine = Color(0xFF4E842D);      // route on light basemap
  static const routeLineNight = Color(0xFFFFFFFF); // route on dark basemap
  static const routeCasing = Color(0x33000000);    // soft outline under route
  static const pinPickup = Color(0xFF12B76A);      // origin marker
  static const pinDropoff = Color(0xFFEF4444);     // destination marker

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
  // Gradients
  // ---------------------------------------------------------------------
  /// The account header field behind the rider's name, phone and avatar.
  ///
  /// Light runs the green ramp [primary] → [primaryDark]; white foregrounds
  /// clear 4.5:1 even at the lightest stop, so the name, phone and balance
  /// stay legible across the whole field. Dark shifts down to [primaryDark] →
  /// [primaryDeep] so the header reads as a deep surface against near-black
  /// rather than a lit panel.
  ///
  /// Runs topRight → bottomLeft: in the RTL layout that puts the lighter stop
  /// behind the avatar and carries the darker stop away from it, so the eye
  /// lands on the portrait first.
  static LinearGradient headerGradient(bool isDark) => LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: isDark
            ? const [primaryDark, primaryDeep]
            : const [primary, primaryDark],
      );

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

    // Every widget-level theme below reads from `go`, the same extension the
    // screens read. Previously these locals came from the `dark*` slate-blue
    // ramp (#0B1220/#1E293B/#334155) while `go` supplied the neutral `night*`
    // ramp (#0E0E10/#26262B/#34343B), so in dark mode Material's own widgets
    // — inputs, chips, dialog copy, hairlines — rendered slate-blue on top of
    // a neutral near-black page. Two dark palettes, one screen. Sourcing both
    // from `go` collapses them into one ramp.
    //
    // In light mode this is a no-op: go.text/muted/border already resolve to
    // lightText/lightMuted/lightBorder, and go.surface to inputFill.
    //
    // The `dark*` tokens stay defined — the Admin and Captain apps still
    // reference them, so removing them would be a breaking change.
    final text = go.text;
    final muted = go.muted;
    final border = go.border;
    final fill = go.surface;

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
      splashFactory: InkSparkle.splashFactory,
      textTheme: _textTheme(text, muted),
      extensions: <ThemeExtension<dynamic>>[go],
      appBarTheme: AppBarTheme(
        backgroundColor: go.bg,
        foregroundColor: go.text,
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
        color: go.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          side: BorderSide(color: go.border, width: 0.8),
        ),
        elevation: isDark ? 0 : 1,
        margin: EdgeInsets.zero,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        labelStyle: AppTokens.font(color: muted, fontSize: 14),
        hintStyle: AppTokens.font(color: muted, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
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
          borderSide: BorderSide(color: go.action, width: 1.8),
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
          backgroundColor: go.action,
          foregroundColor: go.onAction,
          disabledBackgroundColor: go.surface,
          disabledForegroundColor: go.muted,
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
          foregroundColor: go.text,
          minimumSize: const Size.fromHeight(AppTokens.tapTarget),
          side: BorderSide(color: go.border, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
          textStyle: AppTokens.font(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: go.action,
          textStyle: AppTokens.font(fontWeight: FontWeight.w600, fontSize: 15),
        ),
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
          borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        ),
        titleTextStyle: AppTokens.font(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: text,
        ),
        contentTextStyle: AppTokens.font(fontSize: 14, color: muted, height: 1.6),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: go.elevated,
        side: BorderSide(color: border),
        labelStyle: AppTokens.font(fontSize: 12, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppTokens.nightElevated : AppTokens.neutralInk,
        contentTextStyle: AppTokens.font(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        insetPadding: const EdgeInsets.all(AppTokens.spaceMd),
      ),

      dividerTheme: DividerThemeData(color: go.border, space: 1, thickness: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: go.action),

      listTileTheme: ListTileThemeData(
        iconColor: go.muted,
        textColor: go.text,
      ),
      iconTheme: IconThemeData(color: go.text),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: go.panel,
        selectedItemColor: go.action,
        unselectedItemColor: go.muted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
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
