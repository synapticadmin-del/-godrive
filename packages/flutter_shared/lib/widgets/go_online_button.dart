import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The single most important control in a driver app: the switch between
/// earning and not earning.
///
/// Every category leader gives this its own large, unmistakable pill rather
/// than burying it in a menu or a nav-bar gesture. Offline reads as heavy
/// neutral ink; online reads as brand green with a live pulse and a soft
/// halo, so the captain can confirm their state from a glance at a phone
/// mounted on the dashboard.
class GoOnlineButton extends StatefulWidget {
  const GoOnlineButton({
    super.key,
    required this.online,
    required this.onChanged,
    this.busy = false,
    this.enabled = true,
    this.onlineLabel,
    this.offlineLabel,
    this.disabledLabel,
    this.width,
  });

  final bool online;
  final ValueChanged<bool> onChanged;

  /// Shows a spinner and blocks input while the state change is in flight.
  final bool busy;

  /// False while the captain is not yet approved to drive.
  final bool enabled;

  final String? onlineLabel;
  final String? offlineLabel;
  final String? disabledLabel;

  /// Defaults to a comfortable intrinsic width; pass a value to stretch.
  final double? width;

  @override
  State<GoOnlineButton> createState() => _GoOnlineButtonState();
}

class _GoOnlineButtonState extends State<GoOnlineButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    if (widget.online) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant GoOnlineButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The pulse is the live-state signal, so it must follow the actual value
    // rather than only the value present at first build.
    if (widget.online && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.online && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final interactive = widget.enabled && !widget.busy;

    final go = GoTheme.of(context);

    // Fill and foreground are picked as a pair, never independently. The
    // offline pill is deliberately fixed ink in both presentations; the online
    // pill follows the ramp — and after dark the ramp's action is lime, on
    // which the old hardcoded white sat at roughly 1.8:1.
    final Color background;
    final Color foreground;
    if (!widget.enabled) {
      // Was `lightBorder` under `lightMuted` (~3.99:1) in daylight and the
      // legacy `darkSurface` after dark. On the ramp this lands at ~4.47:1 and
      // ~5.41:1 — an inactive control, so formally exempt from the 4.5:1 floor,
      // but worth improving since "pending approval" is the reason the captain
      // cannot earn and they need to be able to read it.
      background = go.surface;
      foreground = go.muted;
    } else if (widget.online) {
      background = go.action;
      foreground = go.onAction;
    } else {
      // "Heavy neutral ink" is the offline signal in both themes, so this pair
      // stays fixed; white on `neutralInk` is ~16:1.
      background = AppTokens.neutralInk;
      foreground = Colors.white;
    }

    final label = !widget.enabled
        ? (widget.disabledLabel ?? (isAr ? 'بانتظار الموافقة' : 'Pending approval'))
        : widget.online
            ? (widget.onlineLabel ?? (isAr ? 'متصل الآن' : 'You are online'))
            : (widget.offlineLabel ?? (isAr ? 'ابدأ العمل' : 'Go online'));

    return Semantics(
      button: true,
      enabled: interactive,
      toggled: widget.online,
      label: label,
      child: GestureDetector(
        onTapDown: interactive ? (_) => setState(() => _pressed = true) : null,
        onTapUp: interactive ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: interactive ? () => setState(() => _pressed = false) : null,
        onTap: interactive ? () => widget.onChanged(!widget.online) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            width: widget.width,
            height: AppTokens.primaryActionHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              boxShadow: widget.online && widget.enabled
                  // Halo the colour actually on screen — a green glow bled out
                  // from under a lime pill after dark.
                  ? AppTokens.glow(go.action)
                  : AppTokens.shadowFloating,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.busy)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(foreground),
                    ),
                  )
                else if (widget.online)
                  _LivePulse(animation: _pulse, color: foreground)
                else
                  Icon(
                    widget.enabled ? Icons.power_settings_new_rounded : Icons.hourglass_top_rounded,
                    size: 20,
                    color: foreground,
                  ),
                const SizedBox(width: AppTokens.spaceSm),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTokens.font(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A breathing dot — the "we are live and listening" signal.
class _LivePulse extends StatelessWidget {
  const _LivePulse({required this.animation, required this.color});

  final Animation<double> animation;

  /// Matches the pill's foreground. This was hardcoded white, which vanished
  /// against the lime night action — the one state where the dot has to be
  /// visible is precisely when the captain is online.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final t = animation.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 10 + (10 * t),
                height: 10 + (10 * t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.35 * (1 - t)),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
