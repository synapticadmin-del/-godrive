import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The app's primary navigation.
///
/// Four destinations with an elevated brand button between them. The centre
/// button is a *shortcut* — it returns to the map and recentres — not a
/// destination of its own, so it deliberately has no label and never shows a
/// selected state. (Going online used to be a hidden side effect of this
/// button; that now lives on an explicit control in the map sheet, where a
/// new captain can actually find it.)
class MainBottomNav extends StatelessWidget {
  const MainBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.onCenterTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback? onCenterTap;

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTokens.darkPanel : Colors.white;
    final borderColor = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;

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
                child: _NavItem(
                  icon: Icons.map_outlined,
                  activeIcon: Icons.map_rounded,
                  label: isAr ? 'الخريطة' : 'Map',
                  active: currentIndex == 0,
                  onTap: () => onTap(0),
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
              Expanded(child: _CenterButton(isDark: isDark, onTap: onCenterTap)),
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactive = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final color = active ? AppTokens.primary : inactive;

    return Semantics(
      button: true,
      selected: active,
      label: label,
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
            Icon(active ? activeIcon : icon, color: color, size: 23),
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
