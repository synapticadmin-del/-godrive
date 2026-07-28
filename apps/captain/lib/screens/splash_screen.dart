import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

/// GoDrive Captain launch screen.
///
/// The old splash dropped a raw video into a white box and hoped for the
/// best: if the asset was slow the captain stared at a bare spinner, and if
/// it failed they got an unstyled logo. This version treats the launch as a
/// composed brand moment —
///
///  * a deep brand-tinted canvas so the screen reads as GoDrive instantly,
///    and so the handoff into the (light) login screen is a deliberate
///    brightening rather than a flash of unstyled white;
///  * the logo lockup and wordmark are always present, with the video
///    layered in as enrichment once it is genuinely ready;
///  * a determinate-feeling progress hairline instead of an anxious spinner;
///  * choreographed entrances, so elements arrive in reading order.
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
    // The splash owns a dark canvas, so the system icons must be light for
    // the duration of this screen.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final controller = VideoPlayerController.asset('assets/videos/splash.mp4');
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setVolume(0); // muted so autoplay is allowed everywhere
      await controller.setLooping(true);
      await controller.play();
      setState(() {
        _controller = controller;
        _videoReady = true;
      });
    } catch (_) {
      // A missing or undecodable asset is not a failure state worth showing
      // the captain — the logo lockup below is a complete design on its own.
      if (mounted) setState(() => _videoReady = false);
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
    _controller?.dispose();
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

  /// The hero: the splash video once it is ready, the logo until then. Both
  /// sit inside the same rounded, softly-lit frame so the swap is a
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
          child: _videoReady && _controller != null
              ? FittedBox(
                  key: const ValueKey('video'),
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                )
              : Padding(
                  key: const ValueKey('logo'),
                  padding: const EdgeInsets.all(38),
                  child: Image.asset(
                    'assets/images/godrive_logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.navigation_rounded,
                      size: 84,
                      color: Colors.white,
                    ),
                  ),
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

  /// An indeterminate hairline rather than a spinner: it signals "loading"
  /// without dominating the composition.
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

/// Two brand-green light sources bled into a near-black field. Cheap to
/// paint, and it gives the flat canvas depth without any image asset.
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
