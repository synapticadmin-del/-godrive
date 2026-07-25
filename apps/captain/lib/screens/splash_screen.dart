import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

/// GoDrive Captain animated splash screen — plays splash.mp4 video centered
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  VideoPlayerController? _controller;
  bool _videoReady = false;
  bool _videoError = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  void _initVideo() async {
    try {
      _controller = VideoPlayerController.asset('assets/videos/splash.mp4');
      await _controller!.initialize();
      if (!mounted) return;
      _controller!.setVolume(0); // Mute to allow autoplay on all web/mobile devices
      _controller!.setLooping(true);
      await _controller!.play();
      setState(() => _videoReady = true);
    } catch (e) {
      if (mounted) {
        setState(() => _videoError = true);
      }
    }
  }

  Future<void> _openSynaptic() async {
    const url = 'https://www.synapticstudio.tech/ar';
    final uri = Uri.parse(url);
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Center Content: Video Player in the exact center of screen
            Center(
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 340,
                  maxHeight: 340,
                ),
                padding: const EdgeInsets.all(16),
                child: _videoReady && _controller != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
                      )
                    : _videoError
                        ? Image.asset(
                            'assets/images/godrive_logo.png',
                            width: 160,
                            height: 160,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.navigation_rounded,
                              size: 80,
                              color: AppTokens.primary,
                            ),
                          ).animate().scale(duration: 800.ms, curve: Curves.easeOutBack)
                        : const SizedBox(
                            width: 44,
                            height: 44,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(AppTokens.primary),
                            ),
                          ),
              ),
            ),

            // Bottom Footer: Created by Synaptic Studio
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Center(
                child: GestureDetector(
                  onTap: _openSynaptic,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Created by',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5),
                              gradient: const LinearGradient(
                                colors: [AppTokens.primary, AppTokens.primaryDark],
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'S',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Synaptic Studio',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppTokens.primary,
                              decoration: TextDecoration.underline,
                              decorationColor: AppTokens.primary.withOpacity(0.4),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.open_in_new, size: 13, color: AppTokens.primary),
                        ],
                      ),
                    ],
                  ),
                ).animate().fade(delay: 400.ms, duration: 600.ms).slideY(begin: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}