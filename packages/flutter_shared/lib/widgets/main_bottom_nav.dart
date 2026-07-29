import 'package:flutter/material.dart';
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
/// the elevated centre destination carries the map. Null keeps the default
/// "الأماكن" first tab, which is what the Rider app uses.
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
/// Four destinations with an elevated brand button between them. By default
/// the centre button is a *shortcut* — it returns to the map and recentres —
/// not a destination of its own, so it deliberately has no label and never
/// shows a selected state. (Going online used to be a hidden side effect of
/// this button; that now lives on an explicit control in the map sheet, where
/// a new captain can actually find it.)
///
/// The first slot is the rider's saved places by default: the map itself is
/// one tap away on the centre button, so the corner slot earns its keep as
/// the quick-reorder surface (Home, Work, …) rather than duplicating the map.
///
/// Two opt-ins let each app re-shape the bar without breaking the other:
///  * [centerDestination] turns the centre slot into a real destination with
///    a label and a selected state (the Captain app puts its map there).
///  * [firstDestination] replaces the first slot's icon/label and adds an
///    optional badge (the Captain app puts "رحلات متاحة" there).
class MainBottomNav extends StatelessWidget {
  const MainBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onCenterTap,
    this.centerDestination,
    this.firstDestination,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Invoked when the centre button is tapped while [centerDestination] is
  /// null — the legacy "back to the map / recentre" shortcut.
  final VoidCallback? onCenterTap;

  /// Opt in to a real centre destination. Null keeps the shortcut behaviour.
  final NavCenterDestination? centerDestination;

  /// Opt in to overriding the first destination. Null keeps "الأماكن".
  final NavFirstDestination? firstDestination;

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTokens.darkPanel : Colors.white;
    final borderColor = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;
    final center = centerDestination;
    final first = firstDestination;

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
              Expanded(
                child: center == null
                    ? _CenterButton(isDark: isDark, onTap: onCenterTap)
                    : _CenterDestinationButton(
                        isDark: isDark,
                        destination: center,
                        active: currentIndex == center.index,
                        onTap: () => onTap(center.index),
                      ),
              ),
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
      ),
    );
  }
}

class _CenterButton extends StatelessWidget {
  const _CenterButton({required this.isDark, required this.onTap});

  final bool isDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        button: true,
        label: 'العودة إلى الخريطة وتوسيط موقعي',
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTokens.primaryLight, AppTokens.primary],
              ),
              boxShadow: AppTokens.glow(AppTokens.primary, opacity: 0.34),
              border: Border.all(
                color: isDark ? AppTokens.darkPanel : Colors.white,
                width: 3,
              ),
            ),
            child: const Icon(
              Icons.my_location_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
        ),
      ),
    );
  }
}

/// The centre slot when it is a real destination rather than a shortcut.
///
/// It keeps the elevated brand circle so the slot still reads as the visual
/// anchor of the bar, but adds the two things a destination needs and a
/// shortcut must not have: a label, and a selected state. A badge carries the
/// count of waiting requests, which is the entire reason a captain would
/// reach for this tab mid-shift.
class _CenterDestinationButton extends StatelessWidget {
  const _CenterDestinationButton({
    required this.isDark,
    required this.destination,
    required this.active,
    required this.onTap,
  });

  final bool isDark;
  final NavCenterDestination destination;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inactive = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final labelColor = active ? AppTokens.primary : inactive;
    final count = destination.badgeCount;

    return Semantics(
      button: true,
      selected: active,
      label: count > 0
          ? '${destination.label} — $count'
          : destination.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTokens.primaryLight, AppTokens.primary],
                    ),
                    boxShadow: AppTokens.glow(
                      AppTokens.primary,
                      opacity: active ? 0.42 : 0.24,
                    ),
                    border: Border.all(
                      color: isDark ? AppTokens.darkPanel : Colors.white,
                      width: 2.5,
                    ),
                  ),
                  child: Icon(
                    destination.icon,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                // Count of waiting requests. Positioned outside the circle so
                // it never occludes the icon.
                if (count > 0)
                  PositionedDirectional(
                    top: -3,
                    end: -5,
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
                        border: Border.all(
                          color: isDark ? AppTokens.darkPanel : Colors.white,
                          width: 1.5,
                        ),
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
            const SizedBox(height: 3),
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
