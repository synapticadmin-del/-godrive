import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
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
  const SplashScreen({super.key, this.onCompleted});

  /// Invoked once the intro has run its full course.
  ///
  /// Optional so the screen stays usable as a plain loading state while the
  /// session is still being restored.
  final VoidCallback? onCompleted;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  VideoPlayerController? _controller;
  bool _videoReady = false;

  /// Fires once the intro has finished — either because the video played all
  /// the way through, or because we fell back to the static lockup.
  bool _completed = false;

  /// Backstop so a stalled decoder can never strand the rider on the splash.
  Timer? _safetyTimer;

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

      // Looping is what previously prevented the intro from ever "finishing".
      // The video must run exactly once, end to end, before we hand over.
      await controller.setLooping(false);

      // Watch playback position so we can detect genuine completion.
      controller.addListener(_onVideoTick);

      await controller.play();

      // Never outstay the clip itself: duration plus a small grace window.
      final duration = controller.value.duration;
      if (duration > Duration.zero) {
        _safetyTimer = Timer(
          duration + const Duration(milliseconds: 750),
          _finish,
        );
      } else {
        _safetyTimer = Timer(const Duration(seconds: 5), _finish);
      }

      setState(() {
        _controller = controller;
        _videoReady = true;
      });
    } catch (_) {
      // Static lockup is already on screen. Give the brand mark a beat to be
      // seen, then continue — a failed video must not block app entry.
      if (mounted) {
        setState(() => _videoReady = false);
        _safetyTimer = Timer(const Duration(milliseconds: 1800), _finish);
      }
    }
  }

  /// Detects the end of playback. `video_player` reports completion by leaving
  /// [VideoPlayerValue.isPlaying] false with the position at the duration.
  void _onVideoTick() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final value = controller.value;
    final duration = value.duration;
    if (duration <= Duration.zero) return;

    if (value.position >= duration && !value.isPlaying) {
      _finish();
    }
  }

  /// Hands control to the app shell exactly once.
  ///
  /// `main.dart` owns routing — it swaps this screen for `HomeScreen` or
  /// `LoginScreen` based on the restored session — so the splash only needs to
  /// report that the intro is done rather than push a route itself.
  void _finish() {
    if (_completed || !mounted) return;
    _completed = true;

    _safetyTimer?.cancel();
    _controller?.removeListener(_onVideoTick);

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
    _safetyTimer?.cancel();
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The intro is a fixed brand moment: the logo, the video and the wordmark
    // are all authored against a light canvas. Following the device's dark
    // mode here would put a light-authored video on a near-black background
    // and invert the wordmark, so the splash is pinned to the light palette
    // regardless of the system setting. Every descendant — including
    // GoTheme.of(context) — resolves against this override.
    final lightTheme = AppTheme.light();
    final go = GoTheme.forBrightness(Brightness.light);

    return Theme(
      data: lightTheme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // Dark status-bar glyphs stay legible on the light splash canvas.
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        child: _buildSplash(go),
      ),
    );
  }

  Widget _buildSplash(GoTheme go) {
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
    final strings = AppStrings.of(context);

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
          style: AppTokens.fontLatin(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: go.text,
          ),
        ).animate().fadeIn(delay: 180.ms, duration: 480.ms),
        const SizedBox(height: 7),
        Text(
          strings.splashTagline,
          style: AppTokens.font(
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
    final strings = AppStrings.of(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.createdByLabel,
            style: AppTokens.fontLatin(
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
                style: AppTokens.fontLatin(
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
