import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';
import 'package:flutter_animate/flutter_animate.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  bool _sending = false;
  bool _sent = false;

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
    return Scaffold(
      backgroundColor: AppTokens.lightBg,
      appBar: AppBar(
        title: const Text('طلب استغاثة (SOS)'),
        backgroundColor: AppTokens.danger,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _sent
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, color: AppTokens.success, size: 100).animate().scale(duration: 500.ms).shake(),
                    const SizedBox(height: 24),
                    const Text(
                      'تم إرسال طلب الاستغاثة بنجاح.',
                      style: TextStyle(color: AppTokens.lightText, fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'فريق الدعم سيقوم بالتواصل معك فوراً وسيتم إبلاغ السلطات المختصة بموقعك.',
                      style: TextStyle(color: AppTokens.lightMuted, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTokens.lightSurface,
                        side: BorderSide(color: AppTokens.lightBorder),
                        minimumSize: const Size(200, 50),
                      ),
                      child: const Text('العودة', style: TextStyle(color: AppTokens.lightText)),
                    )
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'هل أنت في حالة طوارئ؟',
                      style: TextStyle(color: AppTokens.danger, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'استخدم هذا الزر فقط في حالات الخطر الحقيقي (حوادث، سرقة، اعتداء).',
                      style: TextStyle(color: AppTokens.lightText, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),
                    GestureDetector(
                      onTap: _sending ? null : _triggerSos,
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTokens.danger,
                          boxShadow: [
                            BoxShadow(color: AppTokens.danger.withOpacity(0.5), blurRadius: 40, spreadRadius: 10),
                          ],
                        ),
                        child: Center(
                          child: _sending
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text('SOS', style: TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)),
                        ),
                      ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(1, 1), end: const Offset(1.1, 1.1), duration: 1.seconds),
                    ),
                    const SizedBox(height: 48),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء', style: TextStyle(color: AppTokens.lightMuted, fontSize: 18)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
