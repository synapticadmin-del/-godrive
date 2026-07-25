import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

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
  Duration _elapsed = Duration.zero;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Derives elapsed time from the trip's own server timestamp rather than
  /// counting ticks. A tick counter restarts from 00:00 whenever the widget
  /// rebuilds (every offers poll, every rotation, every app resume), so the
  /// captain saw the timer reset repeatedly mid-trip.
  void _tick() {
    if (!mounted) return;
    final startedAtRaw = (widget.trip['started_at'] ??
            widget.trip['arrived_at'] ??
            widget.trip['assigned_at'])
        ?.toString();
    final startedAt = startedAtRaw == null ? null : DateTime.tryParse(startedAtRaw);
    setState(() {
      _elapsed = startedAt == null
          ? _elapsed + const Duration(seconds: 1)
          : DateTime.now().toUtc().difference(startedAt.toUtc());
    });
  }

  String get _formattedTime {
    final total = _elapsed.isNegative ? Duration.zero : _elapsed;
    final h = total.inHours;
    final m = total.inMinutes % 60;
    final s = total.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// Trip transitions hit the network and can fail (409 on a stale status,
  /// connectivity loss). They were wired straight to state.arrived /
  /// state.startTrip as bare VoidCallbacks, so a failure was invisible: the
  /// button appeared to work and the trip silently stayed in its old state.
  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception:', '').trim()),
          backgroundColor: AppTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<CaptainState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = isDark ? AppTokens.darkPanel : AppTokens.lightPanel;
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final muted = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final border = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;

    final status = widget.trip['status'] as String?;
    final fare = (widget.trip['final_fare'] as num?)?.toDouble() ?? (widget.trip['estimated_fare'] as num?)?.toDouble() ?? 0;

    final pickupLat = (widget.trip['pickup_lat'] as num?)?.toDouble();
    final pickupLng = (widget.trip['pickup_lng'] as num?)?.toDouble();
    final dropLat = (widget.trip['dropoff_lat'] as num?)?.toDouble();
    final dropLng = (widget.trip['dropoff_lng'] as num?)?.toDouble();

    final targetLat = (status == 'assigned' || status == 'arrived') ? pickupLat : dropLat;
    final targetLng = (status == 'assigned' || status == 'arrived') ? pickupLng : dropLng;
    final navLabel = (status == 'assigned' || status == 'arrived') ? 'تنقّل للراكب' : 'تنقّل للوجهة';

    String actionText = '';
    Color actionColor = AppTokens.primary;
    VoidCallback? onAction;

    if (status == 'assigned') {
      actionText = 'وصلت لنقطة الالتقاط';
      actionColor = AppTokens.primary;
      onAction = () => _runAction(state.arrived);
    } else if (status == 'arrived') {
      actionText = 'بدء الرحلة';
      actionColor = AppTokens.success;
      onAction = () => _runAction(state.startTrip);
    } else if (status == 'in_progress') {
      actionText = 'إنهاء الرحلة';
      actionColor = AppTokens.accent;
      onAction = () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تأكيد إنهاء الرحلة'),
            content: Text('الأجرة المقدرة: ${fare.toStringAsFixed(2)} ج.م\nهل أنت في نقطة الوصول بالفعل؟'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTokens.success, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('نعم، إنهاء الرحلة'),
              ),
            ],
          ),
        );
        if (ok == true) await _runAction(state.complete);
      };
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
                InkWell(
                  onTap: () async {
                    // canLaunchUrl('tel:') returns false on Android 11+ unless
                    // the scheme is declared in <queries>, which silently made
                    // the call button a no-op. Launch directly and fall back.
                    final uri = Uri(scheme: 'tel', path: '${widget.trip['rider_phone']}');
                    try {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تعذّر فتح تطبيق الاتصال')),
                      );
                    }
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.call, size: 14, color: AppTokens.primary),
                      const SizedBox(width: 4),
                      Text(widget.trip['rider_phone'], style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${fare.toStringAsFixed(2)} ج.م', style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.primary, fontSize: 20, fontWeight: FontWeight.w800)),
              Text(
                widget.trip['final_fare'] != null ? 'الأجرة النهائية' : 'الأجرة المقدرة',
                style: GoogleFonts.ibmPlexSansArabic(color: muted, fontSize: 11),
              ),
            ]),
          ]),
          const SizedBox(height: 16),
          if (targetLat != null && targetLng != null) ...[
            NavigationButton(lat: targetLat, lng: targetLng, label: navLabel),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : onAction,
              style: ElevatedButton.styleFrom(backgroundColor: actionColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd))),
              child: _busy
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(actionText, style: GoogleFonts.ibmPlexSansArabic(fontSize: 17, fontWeight: FontWeight.w700)),
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