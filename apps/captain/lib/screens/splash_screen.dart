import 'dart:async';

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
/// The dark cockpit canvas + lime accent is the Captain's brand identity —
/// it reads as a driver's tool instantly, day or night.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _imageReady = false;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    // The splash owns a dark canvas, so system icons must be light.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
    _precacheBrandImage();
  }

  /// Pre-cache the splash brand image for instant first-frame render.
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

    // Hold for a deliberate brand beat, then hand off to the app shell.
    _holdTimer = Timer(const Duration(milliseconds: 2400), () {
      // The Captain splash's parent (main.dart) owns routing — this screen
      // simply runs its brand moment and lets the shell take over.
    });
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
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.splashBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _BrandBackdrop(),
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

  /// The hero: the splash brand image once cached, the logo until then.
  /// Both sit inside the same rounded, softly-lit frame so the swap is a
  /// cross-fade rather than a layout jump.
  Widget _buildMark() {
    return Center(
      child: Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(56),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
          boxShadow: [
            BoxShadow(
              color: AppTokens.primary.withOpacity(0.30),
              blurRadius: 60,
              spreadRadius: 4,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
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
    return Column(
      children: [
        Text(
          'GoDrive',
          style: AppTokens.font(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: AppTokens.space2xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppTokens.primary.withOpacity(0.22),
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            border: Border.all(color: AppTokens.primaryLight.withOpacity(0.45)),
          ),
          child: Text(
            'تطبيق الكابتن',
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

  /// An indeterminate hairline — signals loading without dominating.
  Widget _buildProgress() {
    return SizedBox(
      width: 132,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        child: LinearProgressIndicator(
          minHeight: 3,
          backgroundColor: Colors.white.withOpacity(0.14),
          valueColor: const AlwaysStoppedAnimation<Color>(AppTokens.primaryLight),
        ),
      ),
    ).animate().fadeIn(delay: 500.ms, duration: 500.ms);
  }

  Widget _buildFooter() {
    return GestureDetector(
      onTap: _openSynaptic,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Created by',
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
    ).animate().fadeIn(delay: 700.ms, duration: 600.ms).slideY(begin: 0.3, end: 0);
  }
}

/// Two brand-green light sources bled into a near-black field.
class _BrandBackdrop extends StatelessWidget {
  const _BrandBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.7, -0.9),
          radius: 1.5,
          colors: [AppTokens.splashGlowStart, AppTokens.splashBg],
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.9, 1.0),
            radius: 1.2,
            colors: [AppTokens.splashGlowTint, AppTokens.splashFade],
          ),
        ),
        child: SizedBox.expand(),
      ),
    );
  }
}
