import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';

/// Error state widget: icon + message + retry button.
///
/// Previously this widget hand-branched on `Theme.of(context).brightness` and
/// read the legacy `darkText`/`darkMuted` ramp, while every surface around it
/// had moved to [GoTheme]'s night ramp — so an error message rendered a
/// slightly different white than the panel it sat on. Worse, the retry button
/// was pinned to `AppTokens.primary`: brand green on a near-black background
/// is roughly 2.6:1, well under the 4.5:1 floor, and the label was a hardcoded
/// Arabic literal that ignored the English locale entirely.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.cloud_off,
  });

  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceXl,
          vertical: AppTokens.spaceLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppTokens.danger),
            const SizedBox(height: AppTokens.spaceMd),
            Text(
              message,
              textAlign: TextAlign.center,
              // Cairo, like the rest of the product. A bare `TextStyle` here
              // fell back to the platform font.
              style: AppTokens.font(fontSize: 14, color: go.text, height: 1.4),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppTokens.spaceMd),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(strings.retryAction),
                style: OutlinedButton.styleFrom(
                  // `go.action` is lime at night, green in daylight — the
                  // token ramp's job is exactly this.
                  foregroundColor: go.action,
                  side: BorderSide(color: go.action),
                  minimumSize: const Size(0, AppTokens.tapTarget),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceLg,
                    vertical: AppTokens.spaceSm,
                  ),
                  textStyle: AppTokens.font(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}