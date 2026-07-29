import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_shared/flutter_shared.dart';

/// Top-level service categories, shown as a horizontal strip above the search
/// field on the home screen — the pattern riders recognise from inDrive.
///
/// These are *service kinds* (a ride, an intercity trip, freight, a tuk-tuk),
/// which is a different axis from [VehicleSelector] below — that one picks the
/// car class once a fare is being quoted.
///
/// The chips carry little vehicle illustrations (Uber-style artwork under
/// assets/images/icons/) rather than Material glyphs: riders recognise the
/// car long before they read the label, and the same artwork appears in both
/// apps so the category strip looks identical for rider and captain.
class VehicleCategoryStrip extends StatelessWidget {
  const VehicleCategoryStrip({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.isArabic,
  });

  final String selected;
  final ValueChanged<String> onChanged;
  final bool isArabic;

  /// Freight and tuk-tuk are temporarily suspended: they stay visible so riders
  /// can see the service exists and is coming, but are not selectable. Removing
  /// the chips outright would read as "this app doesn't do freight" rather than
  /// "not yet".
  static const _categories = <_Category>[
    _Category('ride', 'رحلة', 'Ride', 'assets/images/icons/cat_ride.png'),
    _Category(
      'intercity',
      'سفر',
      'Intercity',
      'assets/images/icons/cat_intercity.png',
    ),
    _Category(
      'freight',
      'الشحن',
      'Freight',
      'assets/images/icons/cat_freight.png',
      enabled: false,
    ),
    _Category(
      'tuktuk',
      'تروسيكل',
      'Tuk-tuk',
      'assets/images/icons/cat_tuktuk.png',
      enabled: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);

    // The bar is a single frosted rail holding frosted chips. Clipping at this
    // level lets the chips' own blur stack against the rail without the
    // scrolling content bleeding past the rounded ends.
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: go.isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.white.withOpacity(0.45),
            borderRadius: BorderRadius.circular(AppTokens.radiusLg),
            border: Border.all(
              color: go.isDark
                  ? Colors.white.withOpacity(0.10)
                  : Colors.white.withOpacity(0.65),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 5),
            physics: const BouncingScrollPhysics(),
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final c = _categories[index];
              final isSelected = c.id == selected;

              return _CategoryChip(
                go: go,
                asset: c.asset,
                label: isArabic ? c.ar : c.en,
                selected: isSelected,
                enabled: c.enabled,
                comingSoonLabel: isArabic ? 'قريباً' : 'Soon',
                onTap: c.enabled ? () => onChanged(c.id) : null,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Category {
  const _Category(this.id, this.ar, this.en, this.asset, {this.enabled = true});
  final String id;
  final String ar;
  final String en;

  /// Uber-style vehicle illustration for this service kind. Lives under
  /// assets/images/icons/ in both apps and replaces the old Material glyph —
  /// riders recognise the little car long before they read the label.
  final String asset;

  /// When false the chip renders dimmed with a "قريباً" badge and ignores taps.
  final bool enabled;
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.go,
    required this.asset,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.comingSoonLabel,
  });

  final GoTheme go;
  final String asset;
  final String label;
  final bool selected;

  /// Null disables the ink response entirely, so a suspended service cannot be
  /// selected even by an accidental long-press.
  final VoidCallback? onTap;

  final bool enabled;

  /// Badge text for suspended services, e.g. "قريباً".
  final String? comingSoonLabel;

  @override
  Widget build(BuildContext context) {
    // Glassmorphism: each chip is a frosted pane rather than a solid tile, so
    // the map keeps showing through the strip that floats above it.
    //
    // The selected chip is the one moment of emphasis — it takes a stronger
    // tint, a brighter rim and a soft coloured glow, which is what separates
    // this from a plain translucent panel.
    final accent = go.isDark ? go.action : AppTokens.primary;
    final selectedFg = go.isDark ? go.onAction : AppTokens.primaryDark;

    // Frosted fill. Dark mode leans on a light veil over near-black; light
    // mode uses white so the blur reads as glass and not as haze.
    final glassBase = go.isDark ? Colors.white : Colors.white;
    final restingFill = glassBase.withOpacity(go.isDark ? 0.08 : 0.62);
    final selectedFill = go.isDark
        ? accent.withOpacity(0.26)
        : accent.withOpacity(0.16);

    final restingRim = glassBase.withOpacity(go.isDark ? 0.14 : 0.75);
    final selectedRim = accent.withOpacity(go.isDark ? 0.85 : 0.60);

    final borderRadius = BorderRadius.circular(AppTokens.radiusMd);

    // A suspended service is dimmed rather than hidden, and loses its ink
    // response, so it reads as "not yet available" instead of "broken".
    // NOTE: the chip no longer runs its own BackdropFilter — the rail above
    // already frosts the whole strip, so a second blur here stacked two GPU
    // blur passes and left a milky haze over the map. The chip keeps its glass
    // look from the translucent fill + rim alone, clipped to its own radius.
    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: ClipRRect(
      borderRadius: borderRadius,
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: 86,
          decoration: BoxDecoration(
            color: selected ? selectedFill : restingFill,
            borderRadius: borderRadius,
            border: Border.all(
              color: selected ? selectedRim : restingRim,
              width: selected ? 1.4 : 1,
            ),
            // Glow on the active chip only; resting chips stay flat so the
            // strip does not turn into a row of competing highlights.
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withOpacity(go.isDark ? 0.42 : 0.28),
                      blurRadius: 16,
                      spreadRadius: 0.5,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Material(
            // Transparent so the frosted fill above remains visible; this
            // exists purely to host the ink response.
            color: Colors.transparent,
            child: InkWell(
              borderRadius: borderRadius,
              onTap: onTap,
              splashColor: accent.withOpacity(0.18),
              highlightColor: accent.withOpacity(0.08),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // The little vehicle illustration carries the identity of
                    // the chip — same artwork in light and dark, sized so the
                    // label still fits under it.
                    Image.asset(
                      asset,
                      width: 34,
                      height: 24,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.directions_car_filled_rounded,
                        size: 22,
                        color: selected
                            ? (go.isDark ? selectedFg : accent)
                            : go.muted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // A suspended service shows "قريباً" in place of its name:
                    // the icon already identifies the service, so the label
                    // slot is better spent explaining why it can't be tapped.
                    Text(
                      enabled ? label : (comingSoonLabel ?? label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTokens.font(
                        fontSize: enabled ? 12 : 11,
                        fontWeight: selected && enabled
                            ? FontWeight.w800
                            : FontWeight.w500,
                        fontStyle:
                            enabled ? FontStyle.normal : FontStyle.italic,
                        color: selected && enabled
                            ? (go.isDark ? selectedFg : AppTokens.primaryDark)
                            : go.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ),
      ),
    );
  }
}

/// Car-class picker shown inside the fare sheet once a route is priced.
///
/// The public API ([fareEstimate], [onSelect]) is unchanged so existing
/// callers keep working; the visuals now follow the active light/dark theme
/// instead of being hardcoded to light surfaces.
class VehicleSelector extends StatefulWidget {
  const VehicleSelector({
    super.key,
    required this.fareEstimate,
    required this.onSelect,
  });

  final Map<String, dynamic>? fareEstimate;
  final Function(String) onSelect;

  @override
  State<VehicleSelector> createState() => _VehicleSelectorState();
}

class _VehicleSelectorState extends State<VehicleSelector> {
  String _selected = 'economy';

  static const _vehicles = <_VehicleClass>[
    _VehicleClass(
      'economy',
      'اقتصادي',
      'Economy',
      'assets/images/icons/class_economy.png',
      1.0,
    ),
    _VehicleClass(
      'comfort',
      'كومفورت',
      'Comfort',
      'assets/images/icons/class_comfort.png',
      1.3,
    ),
    _VehicleClass(
      'xl',
      'عائلي',
      'Family',
      'assets/images/icons/class_xl.png',
      1.6,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    final estimate = widget.fareEstimate;
    final fare = estimate?['fare'];
    final basePrice = fare is Map
        ? (fare['total'] as num?)?.toDouble() ?? 0.0
        : (estimate?['estimatedFare'] as num?)?.toDouble() ?? 0.0;

    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        itemCount: _vehicles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final v = _vehicles[index];
          final isSelected = _selected == v.id;
          final price = (basePrice * v.multiplier).round();

          final selectedBorder = go.isDark ? go.action : AppTokens.primary;
          final selectedTint = go.isDark
              ? go.action.withOpacity(0.14)
              : AppTokens.primaryLight;

          return GestureDetector(
            onTap: () {
              setState(() => _selected = v.id);
              widget.onSelect(_selected);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 112,
              decoration: BoxDecoration(
                color: isSelected ? selectedTint : go.surface,
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                border: Border.all(
                  color: isSelected ? selectedBorder : go.border,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // The class artwork is the choice's identity — same Uber-style
                  // illustrations as the service strip, so both pickers read as
                  // one family.
                  Image.asset(
                    v.asset,
                    width: 52,
                    height: 36,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.directions_car_rounded,
                      size: 34,
                      color: isSelected
                          ? (go.isDark ? go.action : AppTokens.primary)
                          : go.muted,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    isAr ? v.ar : v.en,
                    style: AppTokens.font(
                      fontSize: 13,
                      color: go.text,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isAr ? '$price ج.م' : '$price EGP',
                    style: AppTokens.font(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? (go.isDark ? go.action : AppTokens.primary)
                          : go.muted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VehicleClass {
  const _VehicleClass(this.id, this.ar, this.en, this.asset, this.multiplier);
  final String id;
  final String ar;
  final String en;

  /// Uber-style illustration for this car class (assets/images/icons/).
  final String asset;
  final double multiplier;
}
