import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'godrive_wordmark.dart';

/// Promotes the centre nav button from a shortcut to a real destination.
///
/// The Captain app uses this to surface the map in the centre slot; the
/// Rider app leaves it null and keeps the recentre shortcut.
@immutable
class NavCenterDestination {
  const NavCenterDestination({
    required this.index,
    required this.label,
    required this.icon,
    this.badgeCount = 0,
  });

  /// The index reported through `onTap` and compared against `currentIndex`.
  final int index;

  /// Shown beneath the button. Unlike the four fixed destinations, this label
  /// is caller-supplied — the centre slot means different things per app.
  final String label;

  final IconData icon;

  /// Live count of waiting items. Zero hides the badge.
  final int badgeCount;
}

/// Lets an app override the bar's first destination — icon, label and an
/// optional live badge — without touching the other three fixed slots.
///
/// The Captain app uses this to put "رحلات متاحة" (the browsable queue of
/// nearby requests, with its waiting-count badge) in the first slot. Null
/// keeps the default "الأماكن" (saved places) first tab, which is what the
/// Rider app uses — the map is one tap away on the centre crest.
@immutable
class NavFirstDestination {
  const NavFirstDestination({
    required this.index,
    required this.label,
    required this.icon,
    this.activeIcon,
    this.badgeCount = 0,
    this.onTap,
  });

  final int index;
  final String label;
  final IconData icon;
  final IconData? activeIcon;
  final int badgeCount;

  /// Overrides the tab switch with a custom action — for a slot that opens a
  /// sheet or pushes a route instead of swapping the body.
  ///
  /// When set, `MainBottomNav.onTap` is not called for this slot. [index] is
  /// then only compared against `currentIndex` for the selected state, so pass
  /// an index no tab uses (e.g. `-1`) for a slot that should never look
  /// selected — a sheet is not a destination you are "in".
  final VoidCallback? onTap;
}

/// The first slot is the rider's saved places by default: the map itself is
/// one tap away on the centre button, so the corner slot earns its keep as
/// the quick-reorder surface (Home, Work, …) rather than duplicating the map.

/// The app's primary navigation.
///
/// Four destinations around an elevated brand crest. The bar's top edge is not
/// a straight line: it swells upward into a smooth hump at the centre, and the
/// crest sits inside that swell sharing the bar's own surface colour. The two
/// read as one continuous form — the crest floats *in* the bar rather than
/// being a hard circle stuck on top of it.
///
/// The crest carries the GoDrive wordmark as live text ([GoDriveWordmark]).
/// It used to paint `assets/images/godrive_logo.png`, but that asset is the app
/// icon — a white tile with the wordmark inside — so it covered the crest's own
/// fill with an opaque white square and squeezed the wordmark down to roughly
/// a third of the crest's width. Drawing the lockup as text gives it the full
/// width of the crest, in real brand colours, at any density.
///
/// By default the crest is a *shortcut* — it returns to the map and recentres —
/// not a destination of its own, so it has no label and never shows a selected
/// state.
///
/// Two opt-ins let each app re-shape the bar without breaking the other:
///  * [centerDestination] turns the crest into a real destination with a label
///    and a selected state (the Captain app puts its map there).
///  * [firstDestination] replaces the first slot's icon/label and adds an
///    optional badge or custom tap action.
/// Left null, the original bar is preserved exactly.
class MainBottomNav extends StatelessWidget {
  const MainBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onCenterTap,
    this.centerDestination,
    this.firstDestination,
    this.centerLogoAsset,
  });

  /// Height of the bar proper — the strip the four destinations sit in.
  static const double _barHeight = 66;

  /// How far the centre of the top edge swells above the flat edge.
  static const double _humpRise = 26;

  /// Half-width of the swell. Wide enough that the curve eases in gently
  /// instead of spiking around the crest.
  static const double _humpHalfWidth = 78;

  static const double _crestWidth = 100;
  static const double _crestHeight = 50;

  /// Vertical offset of the crest inside the hump. Small, so the crest nests
  /// in the swell with a thin collar of bar surface above it.
  static const double _crestTop = 3;

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Invoked when the crest is tapped while [centerDestination] is null — the
  /// "back to the map / recentre" shortcut.
  final VoidCallback? onCenterTap;

  /// Opt in to a real centre destination. Null keeps the shortcut behaviour.
  final NavCenterDestination? centerDestination;

  /// Opt in to overriding the first destination. Null keeps "الأماكن".
  final NavFirstDestination? firstDestination;

  /// Optional image to paint in the crest *instead of* the live wordmark.
  ///
  /// Only for white-label builds shipping their own mark. Leave it null for
  /// GoDrive: the bundled `godrive_logo.png` is an app-icon tile and looks
  /// wrong at this size (see the class doc).
  final String? centerLogoAsset;

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final go = GoTheme.of(context);
    final bg = go.panel;
    final borderColor = go.border;
    final center = centerDestination;
    final first = firstDestination;

    final crest = center == null
        ? _CrestButton(
            logoAsset: centerLogoAsset,
            onTap: onCenterTap,
          )
        : _CrestDestination(
            destination: center,
            logoAsset: centerLogoAsset,
            active: currentIndex == center.index,
            onTap: () => onTap(center.index),
          );

    // The shaped surface is painted behind the SafeArea so the fill also
    // covers the home-indicator inset — the bar must not go transparent below
    // the last row of labels.
    return CustomPaint(
      painter: _NavSurfacePainter(
        fill: bg,
        border: borderColor,
        // Casts upward, like the sheet lip token it replaces.
        shadow: Colors.black.withOpacity(go.isDark ? 0.34 : 0.13),
        humpRise: _humpRise,
        humpHalfWidth: _humpHalfWidth,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          // Tall enough to contain the hump AND the crest. The crest used to
          // be pushed outside the parent's bounds with a negative offset,
          // which left the part above the old top edge visually present but
          // untappable — a hit test does not reach a child painted outside its
          // parent's box. Sizing the box to include it makes the whole crest
          // live.
          height: _barHeight + _humpRise,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: _humpRise,
                left: 0,
                right: 0,
                bottom: 0,
                child: Row(
                  children: [
                    Expanded(
                      child: first == null
                          ? _NavItem(
                              icon: Icons.bookmark_outline_rounded,
                              activeIcon: Icons.bookmark_rounded,
                              label: isAr ? 'الأماكن' : 'Places',
                              active: currentIndex == 0,
                              onTap: () => onTap(0),
                            )
                          : _NavItem(
                              icon: first.icon,
                              activeIcon: first.activeIcon ?? first.icon,
                              label: first.label,
                              badgeCount: first.badgeCount,
                              active: currentIndex == first.index,
                              onTap: first.onTap ?? () => onTap(first.index),
                            ),
                    ),
                    Expanded(
                      child: _NavItem(
                        icon: Icons.receipt_long_outlined,
                        activeIcon: Icons.receipt_long_rounded,
                        label: isAr ? 'رحلاتي' : 'Trips',
                        active: currentIndex == 1,
                        onTap: () => onTap(1),
                      ),
                    ),
                    // The crest's reserved slot — the crest itself is painted
                    // above in the Stack, so this is just breathing room.
                    const Expanded(child: SizedBox.shrink()),
                    Expanded(
                      child: _NavItem(
                        icon: Icons.account_balance_wallet_outlined,
                        activeIcon: Icons.account_balance_wallet_rounded,
                        label: isAr ? 'المحفظة' : 'Wallet',
                        active: currentIndex == 2,
                        onTap: () => onTap(2),
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        icon: Icons.person_outline_rounded,
                        activeIcon: Icons.person_rounded,
                        label: isAr ? 'حسابي' : 'Account',
                        active: currentIndex == 3,
                        onTap: () => onTap(3),
                      ),
                    ),
                  ],
                ),
              ),
              // Nested in the swell, not perched on the edge.
              Positioned(
                top: _crestTop,
                left: 0,
                right: 0,
                child: Center(child: crest),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints the bar's surface: a flat strip whose top edge eases up into a
/// centred hump, plus the hairline along that edge and an upward shadow.
///
/// This is what makes the crest read as part of the bar. A plain rectangle
/// with a circle floating over it always looks like two objects.
class _NavSurfacePainter extends CustomPainter {
  const _NavSurfacePainter({
    required this.fill,
    required this.border,
    required this.shadow,
    required this.humpRise,
    required this.humpHalfWidth,
  });

  final Color fill;
  final Color border;
  final Color shadow;
  final double humpRise;
  final double humpHalfWidth;

  /// The top edge, left to right. Both ends of the curve leave and arrive
  /// horizontally, so the swell melts into the straight edge with no crease,
  /// and the apex is flat rather than pointed.
  Path _edgePath(Size size) {
    final cx = size.width / 2;
    // Never let the swell run off a narrow screen.
    final hw = math.min(humpHalfWidth, size.width / 2 - 8);
    final left = cx - hw;
    final right = cx + hw;

    return Path()
      ..moveTo(0, humpRise)
      ..lineTo(left, humpRise)
      ..cubicTo(left + hw * 0.42, humpRise, cx - hw * 0.58, 0, cx, 0)
      ..cubicTo(cx + hw * 0.58, 0, right - hw * 0.42, humpRise, right, humpRise)
      ..lineTo(size.width, humpRise);
  }

  Path _surfacePath(Size size) {
    return Path.from(_edgePath(size))
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final surface = _surfacePath(size);

    // Shadow first: a blurred copy of the same shape, nudged up so the bar
    // casts onto the map above it rather than off the bottom of the screen.
    canvas.save();
    canvas.translate(0, -4);
    canvas.drawPath(
      surface,
      Paint()
        ..color = shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.restore();

    canvas.drawPath(surface, Paint()..color = fill);

    // Hairline on the edge only — stroking the closed shape would draw a line
    // down both sides and across the bottom too.
    canvas.drawPath(
      _edgePath(size),
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_NavSurfacePainter old) =>
      old.fill != fill ||
      old.border != border ||
      old.shadow != shadow ||
      old.humpRise != humpRise ||
      old.humpHalfWidth != humpHalfWidth;
}

/// The crest's visual shell — shared by the shortcut and destination variants
/// so the brand moment never drifts between the two apps.
///
/// Deliberately *not* a circle with a contrasting ring. It is a soft capsule
/// carrying the bar's own surface colour, separated from it only by a brand
/// rim, a whisper of green in the fill and a soft glow underneath. That is
/// what makes it look like it is floating in the bar instead of bolted to it.
class _CrestShell extends StatelessWidget {
  const _CrestShell({
    required this.logoAsset,
    this.active = false,
  });

  final String? logoAsset;

  /// When the crest is a real destination and currently selected, the rim and
  /// glow intensify — the one allowed selected signal on the crest itself.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final accent = go.action;
    final asset = logoAsset;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: MainBottomNav._crestWidth,
      height: MainBottomNav._crestHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // A capsule, so the shape echoes the hump it sits in.
        borderRadius: BorderRadius.circular(MainBottomNav._crestHeight / 2),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: go.isDark
              ? [go.surface, go.panel]
              : [Colors.white, AppTokens.primarySoft],
        ),
        border: Border.all(
          color: accent.withOpacity(active ? 0.55 : 0.32),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(active ? 0.30 : 0.18),
            blurRadius: 16,
            spreadRadius: -2,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: asset == null
            // FittedBox guards the lockup against a locale or density that
            // would otherwise push it past the capsule's edge.
            ? const FittedBox(
                fit: BoxFit.scaleDown,
                child: GoDriveWordmark(fontSize: 17),
              )
            : Image.asset(
                asset,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: GoDriveWordmark(fontSize: 17),
                ),
              ),
      ),
    );
  }
}

/// Adds the shared press feel — a gentle dip on tap-down plus haptics — to
/// whichever crest variant is mounted.
class _CrestPressable extends StatefulWidget {
  const _CrestPressable({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_CrestPressable> createState() => _CrestPressableState();
}

class _CrestPressableState extends State<_CrestPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap?.call();
      },
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        // Shallower than a circular FAB would use: a wide capsule reads as
        // squashed if it dips too far.
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// The crest as a shortcut (Rider): recentres the map, no label, no selected
/// state.
class _CrestButton extends StatelessWidget {
  const _CrestButton({
    required this.logoAsset,
    required this.onTap,
  });

  final String? logoAsset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'العودة إلى الخريطة وتوسيط موقعي',
      child: _CrestPressable(
        onTap: onTap,
        child: _CrestShell(logoAsset: logoAsset),
      ),
    );
  }
}

/// The crest as a real destination (Captain map): adds a label and a selected
/// state beneath it, plus the waiting-count badge above.
class _CrestDestination extends StatelessWidget {
  const _CrestDestination({
    required this.destination,
    required this.logoAsset,
    required this.active,
    required this.onTap,
  });

  final NavCenterDestination destination;
  final String? logoAsset;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    // The selected label used to be brand green on the legacy dark panel —
    // #4E842D on #121A2B is about 3.86:1, under the 4.5:1 floor for an 11px
    // label. On the GoTheme ramp the dark action is lime, which clears 13:1.
    final labelColor = active ? go.action : go.muted;
    final count = destination.badgeCount;
    final haloColor = go.panel;

    return Semantics(
      button: true,
      selected: active,
      label: count > 0 ? '${destination.label} — $count' : destination.label,
      child: _CrestPressable(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                _CrestShell(
                  logoAsset: logoAsset,
                  active: active,
                ),
                // Count of waiting requests. Rides the capsule's shoulder so
                // it never occludes the wordmark.
                if (count > 0)
                  PositionedDirectional(
                    top: -2,
                    end: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(minWidth: 18),
                      decoration: BoxDecoration(
                        color: AppTokens.danger,
                        borderRadius: BorderRadius.circular(
                          AppTokens.radiusPill,
                        ),
                        border: Border.all(color: haloColor, width: 1.5),
                      ),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        textAlign: TextAlign.center,
                        style: AppTokens.font(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTokens.font(
                fontSize: 11,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  /// Optional live badge on the icon (e.g. waiting requests). Zero hides it.
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final color = active ? go.action : go.muted;
    final badgeColor = go.panel;

    return Semantics(
      button: true,
      selected: active,
      label: badgeCount > 0 ? '$label — $badgeCount' : label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // A short brand tick above the active item — a quieter selected
            // signal than tinting the whole item, and it survives at a glance.
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 3,
              width: active ? 20 : 0,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: go.action,
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              ),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(active ? activeIcon : icon, color: color, size: 23),
                if (badgeCount > 0)
                  PositionedDirectional(
                    top: -4,
                    end: -7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(minWidth: 16),
                      decoration: BoxDecoration(
                        color: AppTokens.danger,
                        borderRadius: BorderRadius.circular(
                          AppTokens.radiusPill,
                        ),
                        border: Border.all(color: badgeColor, width: 1.2),
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        textAlign: TextAlign.center,
                        style: AppTokens.font(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTokens.font(
                fontSize: 11,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
