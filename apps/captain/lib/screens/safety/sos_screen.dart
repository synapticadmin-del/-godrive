import 'package:flutter/material.dart';
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

  Future<void> _triggerSos() async {
    setState(() => _sending = true);
    try {
      final state = context.read<CaptainState>();
      await state.apiPost('/safety/sos', {
        'tripId': state.activeTrip?['id'],
        'lat': state.captain?['last_lat'],
        'lng': state.captain?['last_lng'],
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
