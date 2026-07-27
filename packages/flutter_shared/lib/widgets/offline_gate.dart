import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'go_online_button.dart';

/// The banner a captain sees wherever trip work would otherwise appear while
/// they are offline.
///
/// This exists because being offline is not an error state — it is a normal,
/// deliberate mode — but it *is* the reason the screen is empty, and an empty
/// screen with no explanation reads as a broken app. Rather than showing a
/// bare "no trips" message that quietly lies about why, this states the cause
/// and puts the fix directly under the captain's thumb.
///
/// Deliberately high contrast: it floats over map tiles and list surfaces in
/// both brightnesses, so it carries its own opaque panel, border and shadow
/// instead of trusting whatever is behind it.
class GoOnlineCtaBanner extends StatelessWidget {
  const GoOnlineCtaBanner({
    super.key,
    required this.online,
    required this.onToggleOnline,
    this.busy = false,
    this.enabled = true,
    this.title,
    this.message,
    this.compact = false,
    this.margin,
  });

  final bool online;
  final ValueChanged<bool> onToggleOnline;

  /// Blocks input and shows a spinner while the toggle is in flight.
  final bool busy;

  /// False while the captain is not approved — the CTA is then unactionable,
  /// and the copy says so rather than inviting a tap that cannot succeed.
  final bool enabled;

  final String? title;
  final String? message;

  /// Drops the explanatory body copy for tight spaces (e.g. floating over a
  /// map) while keeping the headline and the action.
  final bool compact;

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    final resolvedTitle = title ??
        (enabled
            ? (isAr
                ? 'اتصل بالإنترنت لاستقبال طلبات الرحلات'
                : 'Go online to receive trip requests')
            : (isAr ? 'حسابك قيد المراجعة' : 'Your account is under review'));

    final resolvedMessage = message ??
        (enabled
            ? (isAr
                ? 'لن تصلك إشعارات أو طلبات جديدة وأنت غير متصل.'
                : "You won't receive notifications or new requests while offline.")
            : (isAr
                ? 'سنخطرك فور اعتماد مستنداتك.'
                : "We'll notify you as soon as your documents are approved."));

    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.all(AppTokens.spaceMd),
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(
          color: enabled
              ? AppTokens.warning.withOpacity(0.45)
              : go.border,
          width: 1.4,
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
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (enabled ? AppTokens.warning : go.muted)
                      .withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                child: Icon(
                  enabled
                      ? Icons.wifi_tethering_off_rounded
                      : Icons.hourglass_top_rounded,
                  size: 20,
                  color: enabled ? AppTokens.warning : go.muted,
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      resolvedTitle,
                      style: AppTokens.font(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: go.text,
                        height: 1.35,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 3),
                      Text(
                        resolvedMessage,
                        style: AppTokens.font(
                          fontSize: 12.5,
                          color: go.muted,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMd),
          GoOnlineButton(
            online: online,
            busy: busy,
            enabled: enabled,
            width: double.infinity,
            onChanged: onToggleOnline,
          ),
        ],
      ),
    );
  }
}

/// Full-screen offline state for a tab whose entire purpose is live trip work.
///
/// Centres the CTA in the empty space rather than pinning it to the top, so
/// on an otherwise blank screen the captain's eye lands on the one control
/// that changes anything.
class OfflineTripsPlaceholder extends StatelessWidget {
  const OfflineTripsPlaceholder({
    super.key,
    required this.online,
    required this.onToggleOnline,
    this.busy = false,
    this.enabled = true,
    this.title,
    this.message,
  });

  final bool online;
  final ValueChanged<bool> onToggleOnline;
  final bool busy;
  final bool enabled;
  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Stays scrollable so it still works under a RefreshIndicator and
        // does not overflow on short screens.
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppTokens.spaceXl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: go.surface,
                      ),
                      child: Icon(
                        Icons.wifi_tethering_off_rounded,
                        size: 42,
                        color: go.muted,
                      ),
                    ),
                    GoOnlineCtaBanner(
                      online: online,
                      onToggleOnline: onToggleOnline,
                      busy: busy,
                      enabled: enabled,
                      title: title,
                      message: message,
                      margin: const EdgeInsets.fromLTRB(
                        AppTokens.spaceMd,
                        AppTokens.spaceLg,
                        AppTokens.spaceMd,
                        0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
