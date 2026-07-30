import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Empty state widget: icon + title + optional subtitle + optional CTA button.
/// Used everywhere a list could be empty (history, wallet, trips, offers…).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                // A 10% wash carries the halo on a white card but all but
                // vanishes against the night panel, so the dark case gets a
                // little more body.
                color: go.action.withOpacity(go.isDark ? 0.16 : 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: go.action),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTokens.font(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: go.text,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: AppTokens.font(
                  fontSize: 13,
                  color: go.muted,
                  height: 1.4,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: go.action,
                  foregroundColor: go.onAction,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
