import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

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
/// nearby requests, with its waiting-count badge) in the first slot, while
/// the elevated centre destination carries the map. Null keeps the original
/// "الخريطة" first tab untouched, which is exactly what the Rider app needs.
@immutable
class NavFirstDestination {
  const NavFirstDestination({
    required this.index,
    required this.label,
    required this.icon,
    this.activeIcon,
    this.badgeCount = 0,
  });

  final int index;
  final String label;
  final IconData icon;
  final IconData? activeIcon;
  final int badgeCount;
}

/// The app's primary navigation.
///
/// Four destinations with an elevated brand dome between them. The dome is
/// the visual anchor of the bar: a 62dp circular crest that rises 18dp above
/// the bar's top edge, carrying the GoDrive logo on a brand-gradient field
/// ringed by a surface-coloured halo.
///
/// By default the dome is a *shortcut* — it returns to the map and recentres —
/// not a destination of its own, so it deliberately has no label and never
/// shows a selected state.
///
/// Two opt-ins let each app re-shape the bar without breaking the other:
///  * [centerDestination] turns the dome into a real destination with a label
///    and a selected state (the Captain app puts its map there).
///  * [firstDestination] replaces the first slot's icon/label and adds an
///    optional badge (the Captain app puts "رحلات متاحة" there).
/// Left null, the original bar is preserved exactly — which is what the
/// Rider app relies on.
class MainBottomNav extends StatelessWidget {
  const MainBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onCenterTap,
    this.centerDestination,
    this.firstDestination,
    this.centerLogoAsset = 'assets/images/godrive_logo.png',
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Invoked when the dome is tapped while [centerDestination] is null — the
  /// legacy "back to the map / recentre" shortcut.
  final VoidCallback? onCenterTap;

  /// Opt in to a real centre destination. Null keeps the shortcut behaviour.
  final NavCenterDestination? centerDestination;

  /// Opt in to overriding the first destination. Null keeps "الخريطة".
  final NavFirstDestination? firstDestination;

  /// The brand logo painted inside the dome. Both apps already bundle
  /// `assets/images/godrive_logo.png`, so the default just works; override it
  /// if an app ever ships a different crest (e.g. a white-label build).
  final String centerLogoAsset;

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTokens.darkPanel : Colors.white;
    final borderColor = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;
    final center = centerDestination;
    final first = firstDestination;

    // The bar is taller than the items inside it: the dome overflows the top
    // edge by design, so the Stack must not clip it.
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: borderColor)),
        boxShadow: AppTokens.shadowSheet,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: first == null
                        ? _NavItem(
                            icon: Icons.map_outlined,
                            activeIcon: Icons.map_rounded,
                            label: isAr ? 'الخريطة' : 'Map',
                            active: currentIndex == 0,
                            onTap: () => onTap(0),
                          )
                        : _NavItem(
                            icon: first.icon,
                            activeIcon: first.activeIcon ?? first.icon,
                            label: first.label,
                            badgeCount: first.badgeCount,
                            active: currentIndex == first.index,
                            onTap: () => onTap(first.index),
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
                  // The dome's reserved slot — the dome itself is painted
                  // above the bar in the Stack, so this is just breathing room.
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
              // The dome floats above the bar, vertically centred on the
              // bar's top edge — half in, half out.
              Positioned(
                top: -20,
                child: center == null
                    ? _CenterDomeButton(
                        isDark: isDark,
                        logoAsset: centerLogoAsset,
                        onTap: onCenterTap,
                      )
                    : _CenterDomeDestination(
                        isDark: isDark,
                        destination: center,
                        logoAsset: centerLogoAsset,
                        active: currentIndex == center.index,
                        onTap: () => onTap(center.index),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dome's visual shell — shared by the shortcut and destination variants
/// so the brand moment never drifts between the two apps.
class _DomeShell extends StatelessWidget {
  const _DomeShell({
    required this.isDark,
    required this.logoAsset,
    this.active = false,
  });

  final bool isDark;
  final String logoAsset;

  /// When the dome is a real destination and currently selected, the glow
  /// intensifies — the one allowed selected signal on the crest itself.
  final bool active;

  @override
  Widget build(BuildContext context) {
    final haloColor = isDark ? AppTokens.darkPanel : Colors.white;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTokens.primaryLight, AppTokens.primary],
        ),
        boxShadow: AppTokens.glow(
          AppTokens.primary,
          opacity: active ? 0.46 : 0.34,
        ),
        // The halo ring carves the dome out of the bar — without it the
        // circle would bleed into the bar's background at the seam.
        border: Border.all(color: haloColor, width: 3.5),
      ),
      // Breathing press feel: the whole crest dips slightly on tap-down.
      child: ClipOval(
        child: Padding(
          // Inset so the logo sits as a crest, not a bleed — the green ring
          // of the gradient stays visible around it.
          padding: const EdgeInsets.all(11),
          child: Image.asset(
            logoAsset,
            fit: BoxFit.contain,
            // If the asset is ever missing (white-label build that forgot to
            // bundle it), degrade to the brand monogram rather than a grey
            // error box in the most visible slot of the app.
            errorBuilder: (_, __, ___) => const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'GO',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dome as a shortcut (Rider): recentres the map, no label, no selected
/// state.
class _CenterDomeButton extends StatefulWidget {
  const _CenterDomeButton({
    required this.isDark,
    required this.logoAsset,
    required this.onTap,
  });

  final bool isDark;
  final String logoAsset;
  final VoidCallback? onTap;

  @override
  State<_CenterDomeButton> createState() => _CenterDomeButtonState();
}

class _CenterDomeButtonState extends State<_CenterDomeButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'العودة إلى الخريطة وتوسيط موقعي',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap?.call();
        },
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? 0.9 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: _DomeShell(isDark: widget.isDark, logoAsset: widget.logoAsset),
        ),
      ),
    );
  }
}

/// The dome as a real destination (Captain map): adds a label and a selected
/// state beneath the crest, plus the waiting-count badge above it.
class _CenterDomeDestination extends StatefulWidget {
  const _CenterDomeDestination({
    required this.isDark,
    required this.destination,
    required this.logoAsset,
    required this.active,
    required this.onTap,
  });

  final bool isDark;
  final NavCenterDestination destination;
  final String logoAsset;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_CenterDomeDestination> createState() => _CenterDomeDestinationState();
}

class _CenterDomeDestinationState extends State<_CenterDomeDestination> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final inactive = widget.isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final labelColor = widget.active ? AppTokens.primary : inactive;
    final count = widget.destination.badgeCount;
    final haloColor = widget.isDark ? AppTokens.darkPanel : Colors.white;

    return Semantics(
      button: true,
      selected: widget.active,
      label: count > 0
          ? '${widget.destination.label} — $count'
          : widget.destination.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: _pressed ? 0.9 : 1.0,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  _DomeShell(
                    isDark: widget.isDark,
                    logoAsset: widget.logoAsset,
                    active: widget.active,
                  ),
                  // Count of waiting requests. Rides the dome's shoulder so
                  // it never occludes the crest.
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
            ),
            const SizedBox(height: 4),
            Text(
              widget.destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTokens.font(
                fontSize: 11,
                fontWeight: widget.active ? FontWeight.w800 : FontWeight.w500,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactive = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final color = active ? AppTokens.primary : inactive;
    final badgeColor = isDark ? AppTokens.darkPanel : Colors.white;

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
                color: AppTokens.primary,
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
