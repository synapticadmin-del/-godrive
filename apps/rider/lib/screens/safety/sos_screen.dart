import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTokens.lightPanel,
        title: Text('تحذير', style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.danger)),
        content: Text('هل أنت متأكد من تفعيل حالة الطوارئ؟ سيتم إرسال موقعك للسلطات وإدارة التطبيق.', style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.lightText)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTokens.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الطوارئ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 3));
      } catch (_) {}

      await context.read<AppState>().apiPost('/safety/sos', {
        'tripId': widget.tripId,
        if (pos != null) 'lat': pos.latitude,
        if (pos != null) 'lng': pos.longitude,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال نداء الطوارئ بنجاح مع تحديد موقعك')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _shareTrip() async {
    final url = context.read<AppState>().shareTripUrl(widget.tripId);
    try {
      await context.read<AppState>().apiPost('/safety/share', {'tripId': widget.tripId});
      Share.share('تتبع رحلتي على GoDrive عبر الرابط التالي:\n$url');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('الطوارئ والسلامة', style: GoogleFonts.ibmPlexSansArabic()),
        backgroundColor: AppTokens.lightPanel,
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
                      : Text('SOS', style: GoogleFonts.ibmPlexSansArabic(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(height: 48),
            Text(
              'اضغط على الزر أعلاه في حالة الطوارئ القصوى فقط',
              style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.lightMuted, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _shareTrip,
              icon: const Icon(Icons.share, color: Colors.white),
              label: Text('مشاركة تفاصيل الرحلة', style: GoogleFonts.ibmPlexSansArabic(color: Colors.white, fontSize: 16)),
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
