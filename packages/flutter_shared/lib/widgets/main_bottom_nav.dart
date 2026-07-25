import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A bottom navigation bar matching input_file_3.png design:
///  - White background with subtle top shadow
///  - 4 text+icon items: Home, History, Finance, Account
///  - Elevated center circle with GoDrive logo for Map/Recenter focus
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
    final navBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final navBorder = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);

    return Container(
      decoration: BoxDecoration(
        color: navBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
        border: Border(
          top: BorderSide(color: navBorder, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              // 1. Home
              Expanded(
                child: _NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: isAr ? 'الرئيسية' : 'Home',
                  active: currentIndex == 0,
                  onTap: () => onTap(0),
                ),
              ),

              // 2. History
              Expanded(
                child: _NavItem(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long,
                  label: isAr ? 'السجل' : 'History',
                  active: currentIndex == 1,
                  onTap: () => onTap(1),
                ),
              ),

              // 3. Center GoDrive Elevated Button (Recenter/Map)
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      onTap(0);
                      onCenterTap?.call();
                    },
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTokens.primary.withOpacity(0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(color: AppTokens.primary, width: 2),
                      ),
                      child: Center(
                        child: Image.asset(
                          'assets/images/godrive_logo.png',
                          width: 32,
                          height: 32,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.navigation_rounded,
                            color: AppTokens.primary,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 4. Finance
              Expanded(
                child: _NavItem(
                  icon: Icons.account_balance_wallet_outlined,
                  activeIcon: Icons.account_balance_wallet,
                  label: isAr ? 'المحفظة' : 'Finance',
                  active: currentIndex == 2,
                  onTap: () => onTap(2),
                ),
              ),

              // 5. Account
              Expanded(
                child: _NavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: isAr ? 'الحساب' : 'Account',
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
    final color = active ? AppTokens.primary : const Color(0xFF64748B);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(active ? activeIcon : icon, color: color, size: 24),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}