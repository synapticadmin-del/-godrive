import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../services/app_state.dart';

/// Trip detail screen — shown when a rider taps a completed trip in history.
/// Shows route summary, fare breakdown, captain info, rating, and receipt.
class TripDetailScreen extends StatefulWidget {
  final String tripId;
  const TripDetailScreen({super.key, required this.tripId});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  Map<String, dynamic>? _trip;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await context.read<AppState>().getTrip(widget.tripId);
      setState(() { _trip = res['trip']; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTokens.darkBg : AppTokens.lightBg;
    final panel = isDark ? AppTokens.darkPanel : AppTokens.lightPanel;
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final muted = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final border = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('تفاصيل الرحلة', style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w700)),
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _trip == null
                  ? const EmptyState(icon: Icons.route_outlined, title: 'الرحلة غير موجودة')
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Status + date
                        _headerCard(panel, text, muted, border),
                        const SizedBox(height: 16),
                        // Route
                        _routeCard(panel, text, muted, border),
                        const SizedBox(height: 16),
                        // Fare breakdown
                        _fareCard(panel, text, muted, border),
                        const SizedBox(height: 16),
                        // Captain info
                        if (_trip!['captain_name'] != null)
                          _captainCard(panel, text, muted, border),
                      ],
                    ),
    );
  }

  Widget _headerCard(Color panel, Color text, Color muted, Color border) {
    final status = _trip!['status'] as String? ?? '';
    final fare = (_trip!['final_fare'] as num?)?.toDouble() ?? (_trip!['estimated_fare'] as num?)?.toDouble() ?? 0;
    final date = (_trip!['created_at'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(AppTokens.radiusLg), border: Border.all(color: border)),
      child: Column(children: [
        StatusChip(label: _statusLabel(status), variant: _statusVariant(status), icon: _statusIcon(status)),
        const SizedBox(height: 16),
        Text('${fare.toStringAsFixed(0)} ج.م', style: GoogleFonts.ibmPlexSansArabic(fontSize: 32, fontWeight: FontWeight.w800, color: AppTokens.primary)),
        const SizedBox(height: 4),
        Text(date.substring(0, date.length >= 16 ? 16 : date.length), style: GoogleFonts.ibmPlexSansArabic(fontSize: 13, color: muted)),
      ]),
    );
  }

  Widget _routeCard(Color panel, Color text, Color muted, Color border) {
    final pickup = _trip!['pickup_address'] ?? 'موقف النزول';
    final dropoff = _trip!['dropoff_address'] ?? 'الوجهة';
    final distance = (_trip!['distance_km'] as num?)?.toDouble();
    final duration = (_trip!['duration_min'] as num?)?.toDouble();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(AppTokens.radiusLg), border: Border.all(color: border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('المسار', style: GoogleFonts.ibmPlexSansArabic(fontSize: 16, fontWeight: FontWeight.w700, color: text)),
        const SizedBox(height: 16),
        _routeRow(Icons.location_on, AppTokens.primary, pickup, text),
        if (distance != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: [
              Text('${distance.toStringAsFixed(1)} كم', style: GoogleFonts.ibmPlexSansArabic(fontSize: 12, color: muted)),
              if (duration != null) ...[
                const SizedBox(width: 12),
                Text('${duration.round()} دقيقة', style: GoogleFonts.ibmPlexSansArabic(fontSize: 12, color: muted)),
              ],
            ]),
          ),
        ],
        const SizedBox(height: 12),
        _routeRow(Icons.flag, AppTokens.accent, dropoff, text),
      ]),
    );
  }

  Widget _fareCard(Color panel, Color text, Color muted, Color border) {
    final fare = (_trip!['final_fare'] as num?)?.toDouble() ?? (_trip!['estimated_fare'] as num?)?.toDouble() ?? 0;
    final discount = (_trip!['discount'] as num?)?.toDouble() ?? 0;
    final commission = (_trip!['commission'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(AppTokens.radiusLg), border: Border.all(color: border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('تفاصيل الأجرة', style: GoogleFonts.ibmPlexSansArabic(fontSize: 16, fontWeight: FontWeight.w700, color: text)),
        const SizedBox(height: 12),
        _fareRow('الأجرة', fare, text),
        if (discount > 0) _fareRow('الخصم', -discount, AppTokens.success),
        const Divider(height: 20),
        _fareRow('الإجمالي', fare - discount, AppTokens.primary, bold: true),
        if (commission > 0) ...[
          const SizedBox(height: 4),
          _fareRow('عمولة المنصة', commission, muted, small: true),
        ],
      ]),
    );
  }

  Widget _captainCard(Color panel, Color text, Color muted, Color border) {
    final name = _trip!['captain_name'] ?? 'كابتن';
    final plate = _trip!['vehicle_plate'];
    final rating = _trip!['rating_avg'];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(AppTokens.radiusLg), border: Border.all(color: border)),
      child: Row(children: [
        CircleAvatar(radius: 24, backgroundColor: AppTokens.primary.withOpacity(0.15),
          child: Text(name.substring(0, 1), style: const TextStyle(color: AppTokens.primary, fontWeight: FontWeight.bold, fontSize: 18))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: GoogleFonts.ibmPlexSansArabic(fontSize: 16, fontWeight: FontWeight.w700, color: text)),
          if (plate != null) Text(plate, style: GoogleFonts.ibmPlexSansArabic(fontSize: 13, color: muted)),
        ])),
        if (rating != null)
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: AppTokens.accent.withOpacity(0.15), borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star, color: AppTokens.accent, size: 14),
              const SizedBox(width: 4),
              Text('$rating', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTokens.accent)),
            ])),
      ]),
    );
  }

  Widget _routeRow(IconData icon, Color color, String label, Color text) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: GoogleFonts.ibmPlexSansArabic(fontSize: 14, color: text), maxLines: 2, overflow: TextOverflow.ellipsis)),
    ]);
  }

  Widget _fareRow(String label, double amount, Color color, {bool bold = false, bool small = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: GoogleFonts.ibmPlexSansArabic(fontSize: small ? 11 : 14, color: color.withOpacity(small ? 0.7 : 1))),
        Text('${amount.toStringAsFixed(0)} ج.م',
          style: GoogleFonts.ibmPlexSansArabic(fontSize: small ? 11 : (bold ? 18 : 14), fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color)),
      ]),
    );
  }

  String _statusLabel(String s) => switch (s) {
    'completed' => 'مكتملة',
    'cancelled' => 'ملغية',
    'in_progress' => 'جارية',
    'assigned' => 'مُعيّن',
    _ => s,
  };
  StatusVariant _statusVariant(String s) => switch (s) {
    'completed' => StatusVariant.success,
    'cancelled' => StatusVariant.danger,
    'in_progress' || 'assigned' => StatusVariant.info,
    _ => StatusVariant.neutral,
  };
  IconData _statusIcon(String s) => switch (s) {
    'completed' => Icons.check_circle,
    'cancelled' => Icons.cancel,
    _ => Icons.route,
  };
}