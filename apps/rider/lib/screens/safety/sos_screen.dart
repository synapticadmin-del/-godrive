import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/app_state.dart';

class SosScreen extends StatefulWidget {
  final String tripId;
  const SosScreen({super.key, required this.tripId});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  bool _loading = false;

  Future<void> _triggerSos() async {
    // Resolved before the confirmation dialog — the dialog is itself an await,
    // and every geolocation and network call after it yields again. Capturing
    // up front means nothing here reaches back into a BuildContext that may
    // have been disposed while the SOS was in flight.
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Resolved here for the same reason, and because the dialog must follow the
    // active brightness: it used to be pinned to AppTokens.lightPanel/lightText
    // and lit up a pure-white sheet in the middle of a night trip (T12 F-12-03).
    final go = GoTheme.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: go.panel,
        title: Text('تحذير', style: AppTokens.font(color: AppTokens.danger)),
        // What this dialog promises is what the API actually does: POST
        // /safety/sos writes an open row to sos_alerts and pushes a
        // notification to the admin users. It does not dial 122/123/180 and
        // nothing in this app can (T17 F-17-06). The previous copy — "سيتم
        // إرسال موقعك للسلطات" — told the rider help was on its way from the
        // emergency services, which is the single most dangerous thing this
        // product could get wrong.
        content: Text(
          'هل أنت متأكد من تفعيل حالة الطوارئ؟ سيتم إرسال موقعك الحالي إلى فريق تشغيل GoDrive '
          'لمتابعة رحلتك. التطبيق لا يتصل بالشرطة أو الإسعاف — لو في خطر مباشر اتصل بـ 122 أو 123 بنفسك.',
          style: AppTokens.font(color: go.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: go.muted),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTokens.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الطوارئ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    // The rider may have left the screen while the dialog was open.
    if (!mounted) return;

    setState(() => _loading = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('فعّل خدمة الموقع لإرسال نداء الطوارئ');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('اسمح للتطبيق بالوصول إلى موقعك لإرسال نداء الطوارئ');
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 8));
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) {
        throw Exception('تعذّر تحديد موقعك. حاول مجددًا في مكان مفتوح');
      }

      await appState.apiPost('/safety/sos', {
        'tripId': widget.tripId,
        'lat': pos.latitude,
        'lng': pos.longitude,
      });
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('تم إبلاغ فريق تشغيل GoDrive وإرسال موقعك الحالي')));
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _shareTrip() async {
    try {
      final res = await context.read<AppState>().apiPost(
        '/safety/share',
        {'tripId': widget.tripId},
      );
      final url = res['url'] as String?;
      if (url == null || url.isEmpty) {
        throw Exception('تعذّر إنشاء رابط تتبع الرحلة');
      }
      await Share.share('تتبع رحلتي على GoDrive عبر الرابط التالي:\n$url');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    // The emergency backdrop is deliberately the same near-black red in both
    // brightnesses, exactly as the captain app already does it: a glimpse of
    // this screen has to read as "emergency" and never as a normal app screen.
    // The token lives in AppTokens so both apps share one definition, and it
    // replaces the hardcoded white AppBar that used to blind a rider at night.
    return Scaffold(
      backgroundColor: AppTokens.sosBackdrop,
      appBar: AppBar(
        title: Text(
          'الطوارئ والسلامة',
          style: AppTokens.font(color: Colors.white70),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white70,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: _loading ? null : _triggerSos,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTokens.danger,
                  boxShadow: [
                    BoxShadow(color: AppTokens.danger.withOpacity(0.5), blurRadius: 40, spreadRadius: 10),
                  ],
                ),
                child: Center(
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text('SOS', style: AppTokens.font(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(height: 48),
            Text(
              'اضغط على الزر أعلاه في حالة الطوارئ القصوى فقط',
              style: AppTokens.font(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _shareTrip,
              icon: const Icon(Icons.share, color: Colors.white),
              label: Text('مشاركة تفاصيل الرحلة', style: AppTokens.font(color: Colors.white, fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTokens.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
