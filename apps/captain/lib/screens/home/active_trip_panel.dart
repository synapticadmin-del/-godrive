import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Active trip panel — bottom sheet for the captain during a trip.
/// Shows status, rider info, fare, timer, and the next action button.
/// Includes a "navigate" button (deep-link to Google Maps).
class ActiveTripPanel extends StatefulWidget {
  final Map<String, dynamic> trip;
  const ActiveTripPanel({super.key, required this.trip});

  @override
  State<ActiveTripPanel> createState() => _ActiveTripPanelState();
}

class _ActiveTripPanelState extends State<ActiveTripPanel> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _formattedTime {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<CaptainState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = isDark ? AppTokens.lightPanel : AppTokens.lightPanel;
    final text = isDark ? AppTokens.lightText : AppTokens.lightText;
    final muted = isDark ? AppTokens.lightMuted : AppTokens.lightMuted;
    final border = isDark ? AppTokens.lightBorder : AppTokens.lightBorder;

    final status = widget.trip['status'] as String?;
    final fare = (widget.trip['final_fare'] as num?)?.toDouble() ?? (widget.trip['estimated_fare'] as num?)?.toDouble() ?? 0;
    final dropLat = (widget.trip['dropoff_lat'] as num?)?.toDouble();
    final dropLng = (widget.trip['dropoff_lng'] as num?)?.toDouble();

    String actionText = '';
    Color actionColor = AppTokens.primary;
    VoidCallback? onAction;

    if (status == 'assigned') {
      actionText = 'وصلت لنقطة الالتقاط';
      actionColor = AppTokens.primary;
      onAction = state.arrived;
    } else if (status == 'arrived') {
      actionText = 'بدء الرحلة';
      actionColor = AppTokens.success;
      onAction = state.startTrip;
    } else if (status == 'in_progress') {
      actionText = 'إنهاء الرحلة';
      actionColor = AppTokens.accent;
      onAction = state.complete;
    }

    return Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTokens.radiusXl)),
        border: Border(top: BorderSide(color: border)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(999)))),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: actionColor.withOpacity(0.15), borderRadius: BorderRadius.circular(AppTokens.radiusSm)),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: actionColor))
                  .animate(onPlay: (c) => c.repeat()).fade(duration: 1.seconds),
                const SizedBox(width: 8),
                Text(_statusLabel(status), style: GoogleFonts.ibmPlexSansArabic(color: actionColor, fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
            ),
            Text(_formattedTime, style: GoogleFonts.ibmPlexSansArabic(color: muted, fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            CircleAvatar(radius: 20, backgroundColor: AppTokens.primary.withOpacity(0.12),
              child: const Icon(Icons.person, color: AppTokens.primary, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.trip['rider_name'] ?? 'راكب', style: GoogleFonts.ibmPlexSansArabic(color: text, fontWeight: FontWeight.w700, fontSize: 15)),
              if (widget.trip['rider_phone'] != null)
                Text(widget.trip['rider_phone'], style: GoogleFonts.ibmPlexSansArabic(color: muted, fontSize: 12)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${fare.toStringAsFixed(0)} ج.م', style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.primary, fontSize: 20, fontWeight: FontWeight.w800)),
              Text('الأجرة', style: GoogleFonts.ibmPlexSansArabic(color: muted, fontSize: 11)),
            ]),
          ]),
          const SizedBox(height: 16),
          if (dropLat != null && dropLng != null) ...[
            NavigationButton(lat: dropLat, lng: dropLng, label: 'تنقّل للوجهة'),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(backgroundColor: actionColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd))),
              child: Text(actionText, style: GoogleFonts.ibmPlexSansArabic(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ).animate().slideY(begin: 0.2),
        ]),
      ),
    );
  }

  String _statusLabel(String? status) => switch (status) {
    'assigned' => 'جاري التوجه للعميل',
    'arrived' => 'في انتظار العميل',
    'in_progress' => 'الرحلة جارية',
    _ => status ?? '',
  };
}