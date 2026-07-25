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

    final background = !widget.enabled
        ? (Theme.of(context).brightness == Brightness.dark
            ? AppTokens.darkSurface
            : AppTokens.lightBorder)
        : widget.online
            ? AppTokens.primary
            : AppTokens.neutralInk;

    final label = !widget.enabled
        ? (widget.disabledLabel ?? (isAr ? 'بانتظار الموافقة' : 'Pending approval'))
        : widget.online
            ? (widget.onlineLabel ?? (isAr ? 'متصل الآن' : 'You are online'))
            : (widget.offlineLabel ?? (isAr ? 'ابدأ العمل' : 'Go online'));

    final foreground = widget.enabled ? Colors.white : AppTokens.lightMuted;

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
                  ? AppTokens.glow(AppTokens.primary)
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
                  _LivePulse(animation: _pulse)
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
  const _LivePulse({required this.animation});

  final Animation<double> animation;

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
                  color: Colors.white.withOpacity(0.35 * (1 - t)),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
