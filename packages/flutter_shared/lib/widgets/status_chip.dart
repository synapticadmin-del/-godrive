import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Small colored status chip — success / warning / danger / info / neutral.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.variant = StatusVariant.neutral,
    this.icon,
  });

  final String label;
  final StatusVariant variant;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors(variant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color) _colors(StatusVariant v) {
    switch (v) {
      case StatusVariant.success:
        return (AppTokens.primaryLight, AppTokens.primary);
      case StatusVariant.warning:
        return (const Color(0xFFFEF3C7), AppTokens.warning);
      case StatusVariant.danger:
        return (const Color(0xFFFEE2E2), AppTokens.danger);
      case StatusVariant.info:
        return (const Color(0xFFDBEAFE), const Color(0xFF2563EB));
      case StatusVariant.neutral:
        return (const Color(0xFFF1F5F9), AppTokens.lightMuted);
    }
  }
}

enum StatusVariant { success, warning, danger, info, neutral }