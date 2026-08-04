import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:url_launcher/url_launcher.dart';

/// Tempo Rider launch screen.
///
/// ## What changed, and why
///
/// This screen has now lost its raster brand image entirely. The previous pass
/// had already replaced a looping MP4 with a static PNG — which fixed the
/// aspect-ratio and decode problems the video had — but it left three costs in
/// place:
///
///  * a decode before the first meaningful frame, papered over with a fallback
///    lockup and an [AnimatedSwitcher] that existed only to hide the gap;
///  * an asset to re-cut for every density, and again for every brand change;
///  * a mark that could not respond to the theme, so it carried its own
///    baked-in colour into a screen that has two brightnesses.
///
/// [TempoSplashMark] paints the mark instead. It is resolution-free, costs
/// nothing to decode, recolours itself from the token ramp, and animates as
/// one continuous gesture rather than a fade layered over a bitmap. The
/// precache, the fallback lockup and the switcher are all gone with it —
/// roughly a third of this file was machinery for a problem that no longer
/// exists.
///
/// ## The choreography
///
/// The mark draws itself, the type arrives underneath it on an even beat, and
/// the halo behind everything breathes for the length of the hold. The hold is
/// 2600ms: long enough for the mark's 1500ms entrance to finish and for the
/// pulse to land twice, so the rider sees a resolved mark keeping time rather
/// than an animation cut off mid-gesture.
///
/// The exit is handled one level up: `main.dart` cross-fades this screen into
/// the first real route rather than swapping it out between two frames.
///
/// ## Reduce motion
///
/// `flutter_animate` does not consult the platform reduce-motion flag on its
/// own, so every effect in this file is applied conditionally and the mark is
/// told to paint its resolved state. The screen still composes identically —
/// nothing moves.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onCompleted});

  final VoidCallback? onCompleted;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _completed = false;
  Timer? _holdTimer;

  late final AnimationController _glowCtrl;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    // Long and even: a halo that breathes faster than this stops reading as
    // ambience and starts reading as a progress signal.
    _glowCtrl = AnimationController(
      duration: const Duration(milliseconds: 3200),
      vsync: this,
    );
    _glow = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut);
    // No asset to precache any more, so the hold starts on the first frame
    // instead of waiting on a decode that might never succeed.
    _holdTimer = Timer(const Duration(milliseconds: 2600), _finish);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is not available in initState, so the ticker is gated here.
    if (_reduceMotion) {
      if (_glowCtrl.isAnimating) _glowCtrl.stop();
    } else if (!_glowCtrl.isAnimating) {
      _glowCtrl.repeat(reverse: true);
    }
  }

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  void _finish() {
    if (_completed || !mounted) return;
    _completed = true;
    _holdTimer?.cancel();
    widget.onCompleted?.call();
  }

  Future<void> _openSynaptic() async {
    final uri = Uri.parse('https://www.synapticstudio.tech/ar');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Follow the rider's chosen theme instead of forcing light, so a dark-mode
    // rider does not get a white flash on every cold start.
    final brightness = Theme.of(context).brightness;
    final themed =
        brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light();
    final go = GoTheme.forBrightness(brightness);

    return Theme(
      data: themed,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              go.isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: go.isDark ? Brightness.dark : Brightness.light,
        ),
        child: _buildSplash(go),
      ),
    );
  }

  Widget _buildSplash(GoTheme go) {
    final reduceMotion = _reduceMotion;

    return Scaffold(
      // Dark mode gets the dedicated splash canvas the tokens were cut for;
      // light mode keeps the theme background so nothing flashes on start.
      backgroundColor: go.isDark ? AppTokens.splashBg : go.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Outside the SafeArea on purpose — the halo should bleed behind the
          // status bar rather than stopping at a hard line below it.
          _BrandGlow(go: go, pulse: reduceMotion ? null : _glow),
          SafeArea(
            child: Stack(
              children: [
                Center(
                  child: TempoSplashMark(
                    size: 148,
                    reduceMotion: reduceMotion,
                    color: go.isDark ? go.action : AppTokens.primary,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 100,
                  child: _WordmarkBlock(go: go, reduceMotion: reduceMotion),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 28,
                  child: Center(
                    child: _CreatedByBadge(
                      go: go,
                      onTap: _openSynaptic,
                      reduceMotion: reduceMotion,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The brand halo behind the mark.
///
/// `splashFade` is a fully transparent `splashBg` rather than a transparent
/// black, which is exactly what a gradient's outer stop needs to be: fading to
/// transparent black would drag a grey cast through the midpoint. The light
/// palette gets the same treatment against its own canvas colour.
class _BrandGlow extends StatelessWidget {
  const _BrandGlow({required this.go, required this.pulse});

  final GoTheme go;

  /// Null when the rider has asked the platform to limit animation — the halo
  /// still paints, it just holds still.
  final Animation<double>? pulse;

  @override
  Widget build(BuildContext context) {
    final animation = pulse;
    if (animation == null) return _paint(1);
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) => _paint(animation.value),
    );
  }

  Widget _paint(double t) {
    // Small travel on both axes. The halo widens by a sixth and lifts a
    // quarter of its brightness across the cycle — enough to register as
    // breathing, not enough to read as a pulse.
    final radius = 0.70 + (t * 0.16);
    final intensity = 0.74 + (t * 0.26);

    final colors = go.isDark
        ? [
            AppTokens.splashGlowStart.withOpacity(intensity * 0.9),
            AppTokens.splashGlowTint,
            AppTokens.splashFade,
          ]
        : [
            AppTokens.headerAccent.withOpacity(intensity * 0.85),
            AppTokens.primarySoft.withOpacity(intensity * 0.45),
            go.bg.withOpacity(0),
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          // Biased above centre so the halo sits behind the mark rather than
          // behind the wordmark block near the bottom.
          center: const Alignment(0, -0.22),
          radius: radius,
          colors: colors,
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      // Explicit rather than relying on a childless DecoratedBox falling back
      // to `constraints.smallest` — that only fills because the parent Stack
      // is expanded, which is a long way to reason for a background layer.
      child: const SizedBox.expand(),
    );
  }
}

/// Persistent type block beneath the mark.
///
/// The delays are deliberately late relative to the mark: the ring should be
/// most of the way round before the type starts arriving, so the eye is led
/// from the mark down to the word rather than splitting between the two.
class _WordmarkBlock extends StatelessWidget {
  const _WordmarkBlock({required this.go, required this.reduceMotion});

  final GoTheme go;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final accent = go.isDark ? go.action : AppTokens.primary;
    final strings = AppStrings.of(context);

    // The live lockup rather than a plain Text: the trailing "o" picks up the
    // same accent the mark above is drawn in, which ties the two together.
    final wordmark = TempoWordmark(
      fontSize: 30,
      textColor: go.text,
      accentColor: accent,
    );

    final tagline = Text(
      strings.splashTagline,
      style: AppTokens.font(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: go.muted,
      ),
    );

    final progress = SizedBox(
      width: 120,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          minHeight: 3,
          backgroundColor: go.surface,
          valueColor: AlwaysStoppedAnimation<Color>(accent),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _step(wordmark, 620),
        const SizedBox(height: 6),
        _step(tagline, 730),
        const SizedBox(height: 28),
        _step(progress, 840),
      ],
    );
  }

  /// Fade paired with a short rise — type that only fades in looks like it was
  /// always there at partial opacity; a few pixels of travel gives it intent.
  Widget _step(Widget child, int delayMs) {
    if (reduceMotion) return child;
    return child
        .animate()
        .fadeIn(delay: delayMs.ms, duration: 460.ms)
        .slideY(
          begin: 0.35,
          end: 0,
          delay: delayMs.ms,
          duration: 520.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

class _CreatedByBadge extends StatelessWidget {
  const _CreatedByBadge({
    required this.go,
    required this.onTap,
    required this.reduceMotion,
  });

  final GoTheme go;
  final VoidCallback onTap;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final accent = go.isDark ? go.action : AppTokens.primary;
    final strings = AppStrings.of(context);

    final badge = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.createdByLabel,
            style: AppTokens.font(
              fontSize: 12,
              color: go.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  gradient: LinearGradient(
                    colors: go.isDark
                        ? [go.action, go.actionPressed]
                        : const [AppTokens.primary, AppTokens.primaryDark],
                  ),
                ),
                child: Center(
                  child: Text(
                    'S',
                    style: TextStyle(
                      color: go.isDark ? go.onAction : Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                strings.synapticStudioLabel,
                style: AppTokens.font(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: accent,
                  decoration: TextDecoration.underline,
                  decorationColor: accent.withOpacity(0.4),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.open_in_new_rounded, size: 13, color: accent),
            ],
          ),
        ],
      ),
    );

    if (reduceMotion) return badge;

    // Last beat in the sequence, after the progress bar.
    return badge
        .animate()
        .fade(delay: 980.ms, duration: 560.ms)
        .slideY(begin: 0.3, end: 0, delay: 980.ms, duration: 560.ms);
  }
}
