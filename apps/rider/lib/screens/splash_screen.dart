import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:url_launcher/url_launcher.dart';

/// GoDrive Rider launch screen.
///
/// Replaced the video-based splash with a static brand image. The old splash
/// played a looping MP4 that was never framed for the screen — the aspect
/// ratio didn't match, the decode took a visible moment, and on slow devices
/// the rider saw a blank white gap before the video kicked in. This version
/// paints the brand mark on the very first frame: a high-resolution splash
/// image with choreographed entrance animations layered on top.
///
/// Two things changed in the motion pass.
///
/// **The stage is no longer flat.** `AppTokens` has shipped `splashBg`,
/// `splashGlowStart`, `splashGlowTint` and `splashFade` since the palette was
/// laid down — four tokens that only make sense as a radial brand halo — but
/// nothing ever referenced them and the splash painted a flat page colour.
/// They now drive a halo behind the mark that breathes on a slow cycle, so the
/// screen is alive during the hold instead of frozen.
///
/// **The fallback no longer double-prints the brand.** `_FallbackLockup` used
/// to carry its own wordmark, tagline and progress bar while `_WordmarkBlock`
/// rendered the same three things underneath it, so for the length of the
/// precache the rider saw "GoDrive" twice, the tagline twice and two progress
/// bars. The fallback is now just the logo; the persistent block below owns
/// the type.
///
/// The exit is handled one level up: `main.dart` cross-fades this screen into
/// the first real route rather than swapping it out between two frames.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onCompleted});

  final VoidCallback? onCompleted;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _imageReady = false;
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
    _precacheBrandImage();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // MediaQuery is not available in initState, so the ticker is gated here.
    // flutter_animate does not consult the platform reduce-motion flag on its
    // own, so every effect in this file is applied conditionally.
    if (_reduceMotion) {
      if (_glowCtrl.isAnimating) _glowCtrl.stop();
    } else if (!_glowCtrl.isAnimating) {
      _glowCtrl.repeat(reverse: true);
    }
  }

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  Future<void> _precacheBrandImage() async {
    try {
      await precacheImage(
        const AssetImage('assets/images/splash_brand.png'),
        context,
      );
      if (mounted) setState(() => _imageReady = true);
    } catch (_) {
      if (mounted) setState(() => _imageReady = false);
    }
    // Guarded: the precache is an async gap, so a screen torn down while it
    // was in flight would otherwise arm a timer against a dead State and hold
    // it alive until it fired.
    if (!mounted) return;
    _holdTimer = Timer(const Duration(milliseconds: 2400), _finish);
  }

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
    // Follow the rider's chosen theme instead of forcing light. Previously the
    // splash pinned AppTheme.light() unconditionally, so a dark-mode rider saw
    // a white flash on every cold start before their theme could paint.
    final brightness = Theme.of(context).brightness;
    final themed = brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light();
    final go = GoTheme.forBrightness(brightness);

    return Theme(
      data: themed,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              go.isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness:
              go.isDark ? Brightness.dark : Brightness.light,
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
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: 340, maxHeight: 340),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: AnimatedSwitcher(
                        duration: Duration(
                          milliseconds: reduceMotion ? 0 : 500,
                        ),
                        switchInCurve: Curves.easeOut,
                        child: _imageReady
                            ? _BrandImage(
                                key: const ValueKey('brand'),
                                reduceMotion: reduceMotion,
                              )
                            : _FallbackLockup(
                                key: const ValueKey('fallback'),
                                go: go,
                                reduceMotion: reduceMotion,
                              ),
                      ),
                    ),
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

class _BrandImage extends StatelessWidget {
  const _BrandImage({super.key, required this.reduceMotion});

  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Image.asset(
        'assets/images/splash_brand.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );

    if (reduceMotion) return image;

    return image
        .animate()
        .fadeIn(duration: 480.ms)
        .scale(
          begin: const Offset(0.92, 0.92),
          end: const Offset(1, 1),
          duration: 680.ms,
          curve: Curves.easeOutBack,
        )
        // A single sheen once the mark has settled, timed to land inside the
        // 2400ms hold so it never gets cut off by the route change.
        .shimmer(
          delay: 820.ms,
          duration: 1150.ms,
          color: Colors.white.withOpacity(0.28),
        );
  }
}

/// Shown only while `splash_brand.png` is still decoding.
///
/// Logo only. The wordmark, tagline and progress bar live in
/// `_WordmarkBlock`, which is always on screen — carrying them here as well
/// printed the whole lockup twice during the precache.
class _FallbackLockup extends StatelessWidget {
  const _FallbackLockup({
    super.key,
    required this.go,
    required this.reduceMotion,
  });

  final GoTheme go;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final accent = go.isDark ? go.action : AppTokens.primary;

    final logo = Image.asset(
      'assets/images/godrive_logo.png',
      width: 148,
      height: 148,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Container(
        width: 108,
        height: 108,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Icon(
          Icons.navigation_rounded,
          size: 56,
          color: go.isDark ? go.onAction : Colors.white,
        ),
      ),
    );

    if (reduceMotion) return Center(child: logo);

    return Center(
      child: logo
          .animate()
          .fadeIn(duration: 420.ms)
          .scale(
            begin: const Offset(0.88, 0.88),
            end: const Offset(1, 1),
            duration: 620.ms,
            curve: Curves.easeOutBack,
          ),
    );
  }
}

/// Persistent type block beneath the mark.
///
/// The entrance runs on an even 110ms beat — wordmark, tagline, then the
/// progress bar. The previous delays (180 / 320 / 460 / 500 / 560) were picked
/// per-element and read as a slightly ragged cascade.
class _WordmarkBlock extends StatelessWidget {
  const _WordmarkBlock({required this.go, required this.reduceMotion});

  final GoTheme go;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final accent = go.isDark ? go.action : AppTokens.primary;
    final strings = AppStrings.of(context);

    final wordmark = Text(
      'GoDrive',
      style: AppTokens.font(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: go.text,
      ),
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
        _step(wordmark, 240),
        const SizedBox(height: 6),
        _step(tagline, 350),
        const SizedBox(height: 28),
        _step(progress, 460),
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
        .fade(delay: 600.ms, duration: 560.ms)
        .slideY(begin: 0.3, end: 0, delay: 600.ms, duration: 560.ms);
  }
}
