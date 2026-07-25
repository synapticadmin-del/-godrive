import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

/// GoDrive Rider launch screen.
///
/// Previously this rendered a bare white screen with a spinner until the
/// splash video finished decoding — on a mid-range Android that is a second or
/// more of blank screen at the single most brand-defining moment in the app.
///
/// Now the brand mark is painted on the very first frame and the video fades
/// in on top only once it is genuinely ready. If the video is slow, missing or
/// broken, the rider simply keeps seeing a polished logo lockup rather than
/// discovering that something failed.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  VideoPlayerController? _controller;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final controller =
          VideoPlayerController.asset('assets/videos/splash.mp4');

      // Cap initialisation: a decode that stalls must not hold the brand
      // screen hostage. We fall back to the static lockup instead.
      await controller.initialize().timeout(const Duration(seconds: 3));

      if (!mounted) {
        await controller.dispose();
        return;
      }

      await controller.setVolume(0); // Required for autoplay on web/iOS.
      await controller.setLooping(true);
      await controller.play();

      setState(() {
        _controller = controller;
        _videoReady = true;
      });
    } catch (_) {
      // Static lockup is already on screen — nothing further to do.
      if (mounted) setState(() => _videoReady = false);
    }
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
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);

    return Scaffold(
      backgroundColor: go.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340, maxHeight: 340),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    switchInCurve: Curves.easeOut,
                    child: _videoReady && _controller != null
                        ? ClipRRect(
                            key: const ValueKey('video'),
                            borderRadius: BorderRadius.circular(20),
                            child: AspectRatio(
                              aspectRatio: _controller!.value.aspectRatio,
                              child: VideoPlayer(_controller!),
                            ),
                          )
                        : _BrandLockup(key: const ValueKey('logo'), go: go),
                  ),
                ),
              ),
            ),

            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(child: _CreatedByBadge(go: go, onTap: _openSynaptic)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Static brand mark shown immediately at launch.
class _BrandLockup extends StatelessWidget {
  const _BrandLockup({super.key, required this.go});

  final GoTheme go;

  @override
  Widget build(BuildContext context) {
    final accent = go.isDark ? go.action : AppTokens.primary;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/godrive_logo.png',
          width: 148,
          height: 148,
          fit: BoxFit.contain,
          // If the logo asset is unavailable we still present a deliberate
          // mark rather than a broken-image glyph.
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
        )
            .animate()
            .fadeIn(duration: 420.ms)
            .scale(
              begin: const Offset(0.88, 0.88),
              end: const Offset(1, 1),
              duration: 620.ms,
              curve: Curves.easeOutBack,
            ),
        const SizedBox(height: 22),
        Text(
          'GoDrive',
          style: GoogleFonts.inter(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: go.text,
          ),
        ).animate().fadeIn(delay: 180.ms, duration: 480.ms),
        const SizedBox(height: 7),
        Text(
          'رحلتك، بسعرك',
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            color: go.muted,
          ),
        ).animate().fadeIn(delay: 320.ms, duration: 480.ms),
        const SizedBox(height: 30),
        // A slim indeterminate bar reads as progress without the "stuck
        // spinner" feeling of a centred circular indicator.
        SizedBox(
          width: 132,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: go.surface,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ).animate().fadeIn(delay: 460.ms, duration: 400.ms),
      ],
    );
  }
}

class _CreatedByBadge extends StatelessWidget {
  const _CreatedByBadge({required this.go, required this.onTap});

  final GoTheme go;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = go.isDark ? go.action : AppTokens.primary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Created by',
            style: GoogleFonts.inter(
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
                'Synaptic Studio',
                style: GoogleFonts.inter(
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
    ).animate().fade(delay: 400.ms, duration: 600.ms).slideY(begin: 0.3);
  }
}
