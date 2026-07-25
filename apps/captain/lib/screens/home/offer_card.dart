import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';

/// Offer card for the captain — shows trip details, fare, distance, and a
/// countdown timer for accepting. Haptic feedback + auto-decline on expiry.
class OfferCard extends StatefulWidget {
  final Map<String, dynamic> offer;
  const OfferCard({super.key, required this.offer});

  @override
  State<OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<OfferCard> {
  late int _secondsLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _secondsLeft = 15;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 5) HapticFeedback.lightImpact();
      if (_secondsLeft <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<CaptainState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = isDark ? AppTokens.lightSurface : AppTokens.lightSurface;
    final text = isDark ? AppTokens.lightText : AppTokens.lightText;
    final muted = isDark ? AppTokens.lightMuted : AppTokens.lightMuted;
    final border = isDark ? AppTokens.lightBorder : AppTokens.lightBorder;

    final fare = (widget.offer['estimated_fare'] as num?)?.toDouble() ?? 0;
    final distanceKm = (widget.offer['distanceKm'] as num?)?.toDouble();
    final pickup = widget.offer['pickup_address'] ?? 'موقف الالتقاط';
    final dropoff = widget.offer['dropoff_address'] ?? 'الوجهة';

    final progress = _secondsLeft / 15;
    final urgent = _secondsLeft <= 5;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: urgent ? AppTokens.danger.withOpacity(0.4) : border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top: fare + distance
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppTokens.primary.withOpacity(0.08), AppTokens.accent.withOpacity(0.04)]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTokens.radiusLg)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('رحلة جديدة', style: GoogleFonts.ibmPlexSansArabic(color: muted, fontSize: 13, fontWeight: FontWeight.w600)),
                if (distanceKm != null)
                  Row(children: [
                    Icon(Icons.straighten, size: 14, color: muted),
                    const SizedBox(width: 4),
                    Text('${distanceKm.toStringAsFixed(1)} كم', style: GoogleFonts.ibmPlexSansArabic(fontSize: 12, color: muted)),
                    const SizedBox(width: 12),
                  ]),
                Text('${fare.toStringAsFixed(0)} ج.م', style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.primary, fontSize: 22, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          // Countdown bar
          ClipRect(
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: border,
              valueColor: AlwaysStoppedAnimation<Color>(urgent ? AppTokens.danger : AppTokens.primary),
            ),
          ),
          // Route
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _addressRow(Icons.location_on, AppTokens.primary, pickup, text),
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: SizedBox(height: 16, child: VerticalDivider(color: border, thickness: 2, width: 2)),
              ),
              _addressRow(Icons.flag, AppTokens.accent, dropoff, text),
              const SizedBox(height: 16),
              // Accept + decline
              Row(children: [
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () { HapticFeedback.mediumImpact(); state.accept(widget.offer['id']); },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTokens.primary, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.check, size: 20),
                        const SizedBox(width: 8),
                        Text('قبول', style: GoogleFonts.ibmPlexSansArabic(fontSize: 16, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        context.read<CaptainState>().decline(widget.offer['id']);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: muted, side: BorderSide(color: border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
                      ),
                      child: const Text('رفض'),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _addressRow(IconData icon, Color color, String label, Color text) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: GoogleFonts.ibmPlexSansArabic(fontSize: 14, color: text), maxLines: 2, overflow: TextOverflow.ellipsis)),
    ]);
  }
}