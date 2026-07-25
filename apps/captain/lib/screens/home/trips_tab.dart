import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';

/// Captain's trip history tab — shows completed/active trips with status chips.
class TripsTab extends StatefulWidget {
  const TripsTab({super.key});

  @override
  State<TripsTab> createState() => _TripsTabState();
}

class _TripsTabState extends State<TripsTab> {
  List<Map<String, dynamic>> _trips = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<CaptainState>();
      final res = await state.apiGet('/trips');
      final all = (res['trips'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      // Only trips assigned to this captain
      final mine = all.where((t) => t['captain_id'] == state.user?['id']).toList();
      setState(() {
        _trips = mine;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Both branches previously resolved to the light tokens, so dark mode
    // rendered near-black text on a near-black surface.
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final muted = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Header
          Padding(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              right: 16,
              bottom: 8,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'رحلاتي',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: text,
                ),
              ),
            ),
          ),
          // List
          Expanded(
            child: _loading
                ? const SkeletonList(count: 6)
                : _error != null
                    ? ErrorState(message: _error!, onRetry: _load)
                    : _trips.isEmpty
                        ? const EmptyState(
                            icon: Icons.route_outlined,
                            title: 'لا توجد رحلات بعد',
                            subtitle: 'ستظهر رحلاتك المكتملة هنا',
                          )
                        : RefreshIndicator(
                            color: AppTokens.primary,
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: _trips.length,
                              itemBuilder: (_, i) {
                                final trip = _trips[i];
                                return _TripCard(trip: trip, text: text, muted: muted);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.text, required this.muted});
  final Map<String, dynamic> trip;
  final Color text;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = trip['status'] as String? ?? '';
    // A completed trip's real payout is final_fare; estimated_fare is only the
    // pre-trip quote, so showing it made finished trips display the wrong
    // amount whenever the fare was adjusted on completion.
    final fare = (trip['final_fare'] as num?)?.toDouble() ??
        (trip['estimated_fare'] as num?)?.toDouble() ??
        0;
    final pickup = trip['pickup_address'] ?? 'موقف غير محدد';
    final dropoff = trip['dropoff_address'] ?? 'وجهة غير محددة';
    // substring(0, 10) throws on any timestamp shorter than 10 characters.
    final rawDate = (trip['created_at'] ?? '').toString();
    final date = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTokens.darkPanel : AppTokens.lightPanel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(
          color: isDark ? AppTokens.darkBorder : AppTokens.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(
                label: _statusLabel(status),
                variant: _statusVariant(status),
              ),
              const Spacer(),
              Text(
                '${fare.toStringAsFixed(2)} ج.م',
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTokens.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _routeRow(Icons.location_on, AppTokens.primary, pickup, text),
          const SizedBox(height: 6),
          _routeRow(Icons.flag, AppTokens.accent, dropoff, text),
          const SizedBox(height: 8),
          Text(date, style: TextStyle(fontSize: 11, color: muted)),
        ],
      ),
    );
  }

  Widget _routeRow(IconData icon, Color color, String label, Color text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.ibmPlexSansArabic(fontSize: 13, color: text),
          ),
        ),
      ],
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'searching': return 'بحث';
      case 'offered': return 'عرض';
      case 'assigned': return 'مُعيّن';
      case 'arrived': return 'وصل';
      case 'in_progress': return 'جارية';
      case 'completed': return 'مكتملة';
      case 'cancelled': return 'ملغية';
      default: return s;
    }
  }

  StatusVariant _statusVariant(String s) {
    switch (s) {
      case 'completed': return StatusVariant.success;
      case 'in_progress':
      case 'assigned':
      case 'arrived': return StatusVariant.info;
      case 'cancelled': return StatusVariant.danger;
      default: return StatusVariant.neutral;
    }
  }
}