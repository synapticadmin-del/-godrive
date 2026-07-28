import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../../services/app_state.dart';

/// Persistent bottom navigation on the home shell.
///
/// Two tabs only — the trip flow and the orders/activity list — plus quick
/// theme and language actions so the rider can flip appearance without
/// digging into profile settings. Previously these labels were hardcoded
/// Arabic strings baked into the bar; they now come from [AppStrings] so the
/// bar follows the active locale like every other surface.
class TravelModeBottomBar extends StatelessWidget {
  const TravelModeBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);
    final state = context.read<AppState>();

    return Container(
      decoration: BoxDecoration(
        color: go.panel,
        border: Border(top: BorderSide(color: go.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _TabButton(
              icon: Icons.route_rounded,
              label: strings.travelTabTrip,
              tooltip: strings.backToRidesTooltip,
              selected: currentIndex == 0,
              onTap: () => onTabSelected(0),
            ),
            _TabButton(
              icon: Icons.receipt_long_rounded,
              label: strings.travelTabOrders,
              selected: currentIndex == 1,
              onTap: () => onTabSelected(1),
            ),
            IconButton(
              icon: Icon(
                // Visible brightness, not the enum — see AppState.
                context.watch<AppState>().isDarkActive
                    ? Icons.wb_sunny
                    : Icons.nightlight_round,
              ),
              tooltip: strings.toggleThemeTooltip,
              onPressed: () => context.read<AppState>().toggleTheme(),
            ),
            // The chip reads the language it will switch TO, not the one
            // currently active — tapping it flips the locale.
            Padding(
              padding: const EdgeInsetsDirectional.only(
                end: AppTokens.spaceSm,
              ),
              child: ActionChip(
                avatar: const Icon(Icons.language, size: 16),
                label: Text(
                  strings.languageChipLabel,
                  style: AppTokens.fontLatin(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: go.action,
                  ),
                ),
                backgroundColor: go.surface,
                side: BorderSide(color: go.border),
                tooltip: strings.otherLanguageName,
                onPressed: () => state.toggleLanguage(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final color = selected ? AppTokens.primary : go.muted;
    final button = Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: AppTokens.space2xs),
              Text(
                label,
                style: AppTokens.font(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return tooltip == null
        ? button
        : Tooltip(message: tooltip!, child: button);
  }
}
