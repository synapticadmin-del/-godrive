import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';

/// Emergency SOS screen.
///
/// The design constraint here is different from any other screen in the app:
/// the captain is in distress. They may be shaking. The screen may be tilted.
/// Every tap must work on the first try. That drives three decisions:
///
///  1. Everything that matters is large — the SOS button is 200×200dp, the
///     action buttons are at or above primaryActionHeight.
///  2. Spacing is intentionally generous so accidental tap targets cannot
///     interfere with each other.
///  3. The danger/SOS color palette from AppTokens is used throughout so the
///     captain's nervous system immediately reads "this is serious" — there is
///     no ambient green anywhere on this screen.
///
/// All behavior (GPS fix, fallback chain, POST /safety/sos, navigator pop) is
/// preserved exactly from the previous implementation.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen>
    with SingleTickerProviderStateMixin {
  bool _sending = false;
  bool _sent = false;

  // A subtle pulsing glow behind the SOS button communicates urgency without
  // being distracting while the captain is reading the warning text.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// POST /safety/sos validates `lat` and `lng` as REQUIRED numbers. The old
  /// implementation sent captain['last_lat'/'last_lng'] — the last position the
  /// server had on file, which is null for a captain who has never gone online
  /// and stale otherwise. A null pair failed validation outright, meaning the
  /// panic button silently did nothing in exactly the emergency it exists for.
  ///
  /// A live GPS fix is taken instead, with the last known position and the
  /// server-side value as progressive fallbacks so the alert still goes out
  /// (with whatever location is available) rather than being dropped.
  Future<void> _triggerSos() async {
    setState(() => _sending = true);
    HapticFeedback.heavyImpact();

    final state = context.read<CaptainState>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      double? lat;
      double? lng;

      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 8));
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {
        final last = await Geolocator.getLastKnownPosition();
        lat = last?.latitude ?? (state.captain?['last_lat'] as num?)?.toDouble();
        lng = last?.longitude ?? (state.captain?['last_lng'] as num?)?.toDouble();
      }

      if (lat == null || lng == null) {
        throw Exception('تعذّر تحديد موقعك. فعّل خدمة الموقع وحاول مرة أخرى.');
      }

      await state.apiPost('/safety/sos', {
        if (state.activeTrip?['id'] != null) 'tripId': state.activeTrip!['id'],
        'lat': lat,
        'lng': lng,
      });

      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _sending = false;
          _sent = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception:', '').trim()),
            backgroundColor: AppTokens.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the scaffold background dark red so even a partial glimpse of this
    // screen reads as "emergency" — not a normal app screen.
    const sosBackground = Color(0xFF1A0000);

    return Scaffold(
      backgroundColor: sosBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white70,
        title: Text(
          'طلب استغاثة',
          style: AppTokens.font(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white70,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
          tooltip: 'إغلاق',
        ),
      ),
      body: SafeArea(
        child: _sent ? _buildSentState() : _buildActiveState(),
      ),
    );
  }

  /// Confirmation view — shown after the alert is dispatched successfully.
  /// Calm green against the dark background signals that the captain's action
  /// was received; the copy sets expectations for what happens next.
  Widget _buildSentState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space2xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppTokens.success,
              size: 96,
            ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
            const SizedBox(height: AppTokens.spaceLg),
            Text(
              'تم إرسال طلب الاستغاثة',
              style: AppTokens.font(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTokens.spaceMd),
            Text(
              'فريق الدعم سيتواصل معك فوراً وسيتم إبلاغ السلطات المختصة بموقعك.',
              style: AppTokens.font(
                fontSize: 15,
                color: Colors.white70,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTokens.space2xl),
            SizedBox(
              width: double.infinity,
              height: AppTokens.primaryActionHeight,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                ),
                child: Text(
                  'العودة',
                  style: AppTokens.font(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Active SOS view — the captain has not yet triggered the alert.
  Widget _buildActiveState() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLg,
        vertical: AppTokens.spaceMd,
      ),
      child: Column(
        children: [
          // Warning text at top so the captain reads context before tapping.
          const SizedBox(height: AppTokens.spaceLg),
          Text(
            'هل أنت في حالة طوارئ؟',
            style: AppTokens.font(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: AppTokens.sos,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Text(
            'استخدم هذا الزر فقط في حالات الخطر الحقيقي\n(حوادث، سرقة، اعتداء).',
            style: AppTokens.font(
              fontSize: 15,
              color: Colors.white70,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          // The SOS button occupies the center of the screen — the generous
          // flex ratios above and below ensure it never crowds the text.
          const Spacer(),
          _buildSosButton(),
          const Spacer(),
          // Cancel sits well below the SOS button with ample spacing so a
          // panicking thumb cannot accidentally tap both.
          SizedBox(
            width: double.infinity,
            height: AppTokens.primaryActionHeight,
            child: OutlinedButton(
              onPressed: _sending ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white60,
                side: const BorderSide(color: Colors.white24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
              ),
              child: Text(
                'إلغاء — لست في خطر',
                style: AppTokens.font(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white60,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spaceLg),
        ],
      ),
    );
  }

  Widget _buildSosButton() {
    // The pulsing glow is driven by an AnimationController rather than
    // flutter_animate's repeat, so the pulse runs at a fixed rate regardless
    // of whether the widget rebuilds during the sending state.
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glowRadius = 30.0 + _pulse.value * 20.0;
        return GestureDetector(
          onTap: _sending ? null : _triggerSos,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _sending
                  ? AppTokens.sos.withOpacity(0.7)
                  : AppTokens.sos,
              boxShadow: [
                BoxShadow(
                  color: AppTokens.sos.withOpacity(0.55),
                  blurRadius: glowRadius,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Center(child: child),
          ),
        );
      },
      child: _sending
          ? const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            )
          : Text(
              'SOS',
              style: AppTokens.money(
                fontSize: 52,
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
    );
  }
}
