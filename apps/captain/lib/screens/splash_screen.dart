import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:url_launcher/url_launcher.dart';

/// GoDrive Captain launch screen.
///
/// Replaced the video-based splash with a static brand image. The old splash
/// looped an MP4 that was never framed for this screen — the decode took a
/// visible moment, and the dark canvas clashed with the video's light-authored
/// content. This version paints a high-resolution brand image on the very
/// first frame, layered with choreographed entrance animations.
///
/// ## Motion
///
/// A single [AnimationController] (`_motion`) drives every looping element so
/// the whole screen costs one ticker and all the motion stays in phase:
///
///  * the two brand glows in the backdrop drift in slow opposite orbits;
///  * three radar rings expand behind the logo — the dispatch metaphor,
///    "we are already looking for work around you";
///  * the logo's glow breathes;
///  * a sheen sweeps the GoDrive wordmark every few seconds;
///  * the progress bar slides a light from end to end;
///  * road dashes scroll across the lower edge of the screen — the car is
///    already moving before the first screen loads.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _imageReady = false;

  /// The one shared clock for every looping animation on this screen.
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
    _precacheBrandImage();
  }

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
  }

  Future<void> _openSynaptic() async {
    final uri = Uri.parse('https://www.synapticstudio.tech/ar');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.splashBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _MotionBackdrop(t: _motion),
          // The scrolling road, low on the canvas, behind the content.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RoadDashesPainter(
                  color: AppTokens.primaryLight,
                  t: _motion,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),
                _buildMark(),
                const SizedBox(height: AppTokens.spaceLg),
                _buildWordmark(),
                const Spacer(flex: 3),
                _buildProgress(),
                const SizedBox(height: AppTokens.spaceXl),
                _buildFooter(),
                const SizedBox(height: AppTokens.spaceLg),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMark() {
    return AnimatedBuilder(
      animation: _motion,
      builder: (context, child) {
        // The glow breathes: opacity and blur ride a slow sine so the logo
        // reads as alive rather than pasted on.
        final breathe = 0.5 + 0.5 * math.sin(_motion.value * 2 * math.pi);
        return SizedBox(
          width: 300,
          height: 300,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Dispatch radar — three rings expanding outward and fading.
              CustomPaint(
                size: const Size(300, 300),
                painter: _RadarPainter(
                  color: AppTokens.primaryLight,
                  t: _motion,
                ),
              ),
              Center(
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(56),
                    border:
                        Border.all(color: Colors.white.withOpacity(0.10)),
                    boxShadow: [
                      BoxShadow(
                        color: AppTokens.primary
                            .withOpacity(0.24 + 0.12 * breathe),
                        blurRadius: 52 + 18 * breathe,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: child,
                ),
              ),
            ],
          ),
        );
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: _imageReady
            ? ClipRRect(
                key: const ValueKey('brand'),
                borderRadius: BorderRadius.circular(56),
                child: Image.asset(
                  'assets/images/splash_brand.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _logoFallback(),
                ),
              )
            : Padding(
                key: const ValueKey('logo'),
                padding: const EdgeInsets.all(38),
                child: _logoFallback(),
              ),
      ),
    )
        .animate()
        .fadeIn(duration: 600.ms)
        .scale(
          begin: const Offset(0.86, 0.86),
          end: const Offset(1, 1),
          duration: 700.ms,
          curve: Curves.easeOutBack,
        );
  }

  Widget _logoFallback() {
    return Image.asset(
      'assets/images/godrive_logo.png',
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.navigation_rounded,
        size: 84,
        color: Colors.white,
      ),
    );
  }

  Widget _buildWordmark() {
    final strings = AppStrings.of(context);
    return Column(
      children: [
        // Base colour is slightly dimmed so the passing sheen has contrast
        // to play against; shimmer on full-white text would be invisible.
        Text(
          'GoDrive',
          style: AppTokens.font(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            color: Colors.white.withOpacity(0.82),
            letterSpacing: -1,
          ),
        )
            .animate(onPlay: (c) => c.repeat())
            .shimmer(
              delay: 1200.ms,
              duration: 1800.ms,
              color: Colors.white,
            ),
        const SizedBox(height: AppTokens.space2xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppTokens.primary.withOpacity(0.22),
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            border:
                Border.all(color: AppTokens.primaryLight.withOpacity(0.45)),
          ),
          child: Text(
            strings.captainAppBadge,
            style: AppTokens.font(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white.withOpacity(0.95),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 250.ms, duration: 600.ms).slideY(begin: 0.25, end: 0);
  }

  Widget _buildProgress() {
    // A light that enters from one end and leaves through the other — the
    // familiar indeterminate-progress read, but branded and on the same
    // clock as everything else.
    const trackWidth = 132.0;
    const beamWidth = trackWidth * 0.45;
    return SizedBox(
      width: trackWidth,
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.white.withOpacity(0.14)),
            AnimatedBuilder(
              animation: _motion,
              builder: (context, child) {
                final x = -beamWidth +
                    (trackWidth + beamWidth * 2) * _motion.value;
                return Transform.translate(
                  offset: Offset(x, 0),
                  child: child,
                );
              },
              child: Container(
                width: beamWidth,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      AppTokens.primaryLight,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 500.ms, duration: 500.ms);
  }

  Widget _buildFooter() {
    // ConstrainedBox ensures the tap area meets the 48dp minimum even though
    // the visible studio badge renders at ~33dp (rule 6).
    return GestureDetector(
      onTap: _openSynaptic,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTokens.tapTarget),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          Text(
            AppStrings.of(context).createdByLabel,
            style: AppTokens.font(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: AppTokens.space2xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  gradient: const LinearGradient(
                    colors: [AppTokens.primaryLight, AppTokens.primary],
                  ),
                ),
                child: Center(
                  child: Text(
                    'S',
                    style: AppTokens.font(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.spaceXs),
              Text(
                'Synaptic Studio',
                style: AppTokens.font(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withOpacity(0.92),
                ),
              ),
              const SizedBox(width: AppTokens.space2xs),
              Icon(
                Icons.open_in_new,
                size: 13,
                color: Colors.white.withOpacity(0.6),
              ),
            ],
          ),
        ],
        ),
      ),
    ).animate().fadeIn(delay: 700.ms, duration: 600.ms).slideY(begin: 0.3, end: 0);
  }
}

/// The brand glows, drifting. The old backdrop painted both radial gradients
/// at fixed alignments; now each glow centre rides a slow orbit (the two
/// orbits run at different rates so they never sync into a visible pattern).
class _MotionBackdrop extends StatelessWidget {
  const _MotionBackdrop({required this.t});

  final Animation<double> t;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) {
        final v = t.value * 2 * math.pi;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(
                -0.7 + 0.12 * math.cos(v),
                -0.9 + 0.10 * math.sin(v),
              ),
              radius: 1.5,
              colors: const [AppTokens.splashGlowStart, AppTokens.splashBg],
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(
                  0.9 - 0.10 * math.cos(v * 0.8),
                  1.0 - 0.12 * math.sin(v * 0.8),
                ),
                radius: 1.2,
                colors: const [AppTokens.splashGlowTint, AppTokens.splashFade],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

/// Three rings expanding out of the logo and dissolving — staggered by a
/// third of the loop so one ring is always mid-flight. Painted via the
/// shared controller's `repaint` listenable, so no extra ticker.
class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.color, required Animation<double> t})
      : _t = t,
        super(repaint: t);

  final Color color;
  final Animation<double> _t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.width / 2;
    const rings = 3;
    for (var i = 0; i < rings; i++) {
      final phase = (_t.value + i / rings) % 1.0;
      final radius = maxRadius * (0.36 + 0.64 * phase);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withOpacity((1 - phase) * 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) => false;
}

/// Road dashes scrolling across the lower edge of the canvas, over a faint
/// static centre line. Two dash-lengths per loop, so the motion reads as
/// driving rather than ticking.
class _RoadDashesPainter extends CustomPainter {
  _RoadDashesPainter({required this.color, required Animation<double> t})
      : _t = t,
        super(repaint: t);

  final Color color;
  final Animation<double> _t;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * 0.865;
    const dashWidth = 26.0;
    const gap = 18.0;
    const unit = dashWidth + gap;

    // Faint static centre line under the moving dashes.
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = color.withOpacity(0.14)
        ..strokeWidth = 1.0,
    );

    final paint = Paint()
      ..color = color.withOpacity(0.55)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final offset = _t.value * unit * 2;
    for (var x = -unit + offset; x < size.width + unit; x += unit) {
      canvas.drawLine(Offset(x, y), Offset(x + dashWidth, y), paint);
    }
  }

  @override
  bool shouldRepaint(_RoadDashesPainter oldDelegate) => false;
}
