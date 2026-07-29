import 'package:flutter/material.dart';
import 'package:flutter_shared/flutter_shared.dart';

/// Bottom bar shown while the rider is in intercity ("سفر") mode.
///
/// Intercity is a different job from a city ride: the rider is arranging a
/// long-distance seat, a car, or a parcel, and then waiting on offers. The
/// four-destination [MainBottomNav] is the wrong shape for that, so travel mode
/// swaps in a focused two-tab bar — the booking view and the rider's own
/// requests — matching the intercity flow in the design.
///
/// Ride mode keeps [MainBottomNav] untouched.
class TravelModeBottomBar extends StatelessWidget {
  const TravelModeBottomBar({
    super.key,
    required this.currentTab,
    required this.onTabChanged,
    required this.onExitTravelMode,
    this.pendingRequests = 0,
  });

  /// Which of the two tabs is active.
  final TravelTab currentTab;

  final ValueChanged<TravelTab> onTabChanged;

  /// Leaves intercity mode and returns to the city-ride experience.
  ///
  /// Travel mode replaces the service strip, so without an explicit exit the
  /// rider would have no way back to a normal ride — this is that way back.
  final VoidCallback onExitTravelMode;

  /// Badge count on the requests tab. Zero hides the badge.
  final int pendingRequests;

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final go = GoTheme.of(context);
    final bg = go.panel;
    final borderColor = go.border;

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
              // Escape hatch back to city rides, kept narrow so the two real
              // tabs stay dominant.
              _ExitButton(
                go: go,
                tooltip: isAr ? 'رجوع إلى الرحلات' : 'Back to rides',
                onTap: onExitTravelMode,
              ),
              Expanded(
                child: _TravelNavItem(
                  go: go,
                  icon: Icons.alt_route_outlined,
                  activeIcon: Icons.alt_route_rounded,
                  label: isAr ? 'رحلة' : 'Trip',
                  active: currentTab == TravelTab.trip,
                  onTap: () => onTabChanged(TravelTab.trip),
                ),
              ),
              Expanded(
                child: _TravelNavItem(
                  go: go,
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long_rounded,
                  label: isAr ? 'طلباتي' : 'My orders',
                  active: currentTab == TravelTab.orders,
                  badgeCount: pendingRequests,
                  onTap: () => onTabChanged(TravelTab.orders),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The two destinations available in intercity mode.
enum TravelTab { trip, orders }

class _ExitButton extends StatelessWidget {
  const _ExitButton({
    required this.go,
    required this.tooltip,
    required this.onTap,
  });

  final GoTheme go;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 58,
          child: Center(
            child: Icon(
              Icons.arrow_back_rounded,
              color: go.muted,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _TravelNavItem extends StatelessWidget {
  const _TravelNavItem({
    required this.go,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badgeCount = 0,
  });

  final GoTheme go;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final accent = go.action;
    final color = active ? accent : go.muted;

    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The badge is stacked on the icon rather than the whole item so it
            // stays pinned to the glyph as the label width changes with locale.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(active ? activeIcon : icon, color: color, size: 25),
                if (badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(minWidth: 17),
                      decoration: BoxDecoration(
                        color: AppTokens.danger,
                        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                      ),
                      child: Text(
                        badgeCount > 9 ? '9+' : '$badgeCount',
                        textAlign: TextAlign.center,
                        style: AppTokens.font(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTokens.font(
                fontSize: 12,
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
