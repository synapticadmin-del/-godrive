import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'go_online_button.dart';

/// Shown wherever trip work would otherwise appear while the captain is
/// offline.
///
/// A captain who is offline receives no FCM pushes and no offers, but the
/// old screens simply rendered an empty list — indistinguishable from "online
/// but no demand right now". That ambiguity costs the captain money: they sit
/// waiting for work that was never going to arrive. This states the cause and
/// puts the fix directly under it.
class OfflineGuardBanner extends StatelessWidget {
  const OfflineGuardBanner({
    super.key,
    required this.online,
    required this.onToggleOnline,
    this.busy = false,
    this.isApproved = true,
    this.compact = false,
  });

  final bool online;
  final ValueChanged<bool> onToggleOnline;
  final bool busy;

  /// A captain still awaiting document approval cannot go online at all, so
  /// the CTA is disabled and the copy explains why.
  final bool isApproved;

  /// Tighter padding for use inside a sheet rather than a full page.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);

    final title = isApproved
        ? 'أنت غير متصل الآن'
        : 'حسابك قيد المراجعة';
    final body = isApproved
        ? 'لن تصلك إشعارات أو طلبات رحلات وأنت غير متصل. اضغط للاتصال وبدء استقبال الرحلات.'
        : 'سنخطرك فور اعتماد مستنداتك، وعندها يمكنك الاتصال واستقبال الرحلات.';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        compact ? AppTokens.spaceMd : AppTokens.spaceLg,
      ),
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(
          color: isApproved
              ? AppTokens.warning.withOpacity(0.45)
              : go.border,
          width: 1.5,
        ),
        boxShadow: AppTokens.shadowFloating,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (isApproved ? AppTokens.warning : go.muted)
                      .withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                child: Icon(
                  isApproved
                      ? Icons.wifi_tethering_off_rounded
                      : Icons.hourglass_top_rounded,
                  color: isApproved ? AppTokens.warning : go.muted,
                  size: 23,
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTokens.font(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: go.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      style: AppTokens.font(
                        fontSize: 13,
                        color: go.muted,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMd),
          GoOnlineButton(
            online: online,
            busy: busy,
            enabled: isApproved,
            width: double.infinity,
            offlineLabel: 'اتصل الآن لاستقبال الرحلات',
            onChanged: onToggleOnline,
          ),
        ],
      ),
    );
  }
}
