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
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onCompleted});

  final VoidCallback? onCompleted;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _imageReady = false;
  bool _completed = false;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = AppTheme.light();
    final go = GoTheme.forBrightness(Brightness.light);

    return Theme(
      data: lightTheme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
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
                  padding: const EdgeInsets.all(24),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    switchInCurve: Curves.easeOut,
                    child: _imageReady
                        ? _BrandImage(key: const ValueKey('brand'))
                        : _FallbackLockup(key: const ValueKey('fallback'), go: go),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 100,
              child: _WordmarkBlock(go: go),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Center(child: _CreatedByBadge(go: go, onTap: _openSynaptic)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandImage extends StatelessWidget {
  const _BrandImage({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Image.asset(
        'assets/images/splash_brand.png',
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    )
        .animate()
        .fadeIn(duration: 480.ms)
        .scale(
          begin: const Offset(0.92, 0.92),
          end: const Offset(1, 1),
          duration: 680.ms,
          curve: Curves.easeOutBack,
        );
  }
}

class _FallbackLockup extends StatelessWidget {
  const _FallbackLockup({super.key, required this.go});

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
          style: AppTokens.font(
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

class _WordmarkBlock extends StatelessWidget {
  const _WordmarkBlock({required this.go});

  final GoTheme go;

  @override
  Widget build(BuildContext context) {
    final accent = go.isDark ? go.action : AppTokens.primary;
    final strings = AppStrings.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'GoDrive',
          style: AppTokens.font(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: go.text,
          ),
        ).animate().fadeIn(delay: 300.ms, duration: 500.ms),
        const SizedBox(height: 6),
        Text(
          strings.splashTagline,
          style: AppTokens.font(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: go.muted,
          ),
        ).animate().fadeIn(delay: 420.ms, duration: 500.ms),
        const SizedBox(height: 28),
        SizedBox(
          width: 120,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: go.surface,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ).animate().fadeIn(delay: 560.ms, duration: 400.ms),
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
    ).animate().fade(delay: 500.ms, duration: 600.ms).slideY(begin: 0.3);
  }
}
