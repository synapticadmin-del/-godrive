import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';
import 'package:google_fonts/google_fonts.dart';
import 'offer_card.dart';
import 'active_trip_panel.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// The captain's map tab: top status bar + offers sheet / active trip panel.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.mapController});

  final MapController mapController;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<CaptainState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelColor = isDark ? AppTokens.darkPanel : AppTokens.lightPanel;
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final muted = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final border = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;

    final approval =
        state.captain?['approval_status'] ?? state.captain?['status'];
    final isApproved = approval == 'approved';
    final activeTrip = state.activeTrip;
    final offers = state.offers;

    return Stack(
      children: [
        // Active trip markers
        if (activeTrip != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(
                  (activeTrip['pickup_lat'] as num).toDouble(),
                  (activeTrip['pickup_lng'] as num).toDouble(),
                ),
                child: const Icon(Icons.location_on, color: AppTokens.primary, size: 36),
              ),
              if (activeTrip['dropoff_lat'] != null)
                Marker(
                  point: LatLng(
                    (activeTrip['dropoff_lat'] as num).toDouble(),
                    (activeTrip['dropoff_lng'] as num).toDouble(),
                  ),
                  child: const Icon(Icons.flag, color: AppTokens.accent, size: 36),
                ),
            ],
          ),

        // Top status bar
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 60, // leave room for SOS FAB
          right: 16,
          child: _buildStatusBar(panelColor, text, muted, border, state, isApproved),
        ),

        // Approval banner
        if (!isApproved)
          Positioned(
            top: MediaQuery.of(context).padding.top + 70,
            left: 16,
            right: 16,
            child: _buildApprovalBanner(),
          ),

        // Bottom: offers sheet or active trip panel
        Align(
          alignment: Alignment.bottomCenter,
          child: activeTrip != null
              ? ActiveTripPanel(trip: activeTrip)
              : _buildOffersSheet(panelColor, border, muted, offers),
        ),
      ],
    );
  }

  Widget _buildStatusBar(
    Color bg, Color text, Color muted, Color border,
    CaptainState state, bool isApproved,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppTokens.primary.withOpacity(0.15),
            radius: 16,
            child: Text(
              state.user?['name']?.substring(0, 1) ?? 'C',
              style: const TextStyle(color: AppTokens.primary, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.user?['name'] ?? 'كابتن',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: state.offersWsStatus == 'connected'
                            ? AppTokens.success
                            : AppTokens.danger,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isApproved
                          ? (state.online ? 'متصل الآن' : 'غير متصل')
                          : 'بانتظار الموافقة',
                      style: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 11,
                        color: isApproved
                            ? (state.online ? AppTokens.success : muted)
                            : AppTokens.accent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalBanner() {
    return GestureDetector(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTokens.accent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(color: AppTokens.accent.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTokens.accent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'حسابك قيد المراجعة. ارفع المستندات لتفعيل الحساب.',
                style: GoogleFonts.ibmPlexSansArabic(
                  color: AppTokens.accent,
                  fontSize: 12,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTokens.accent, size: 18),
          ],
        ),
      ).animate().fade().slideY(begin: -0.2),
    );
  }

  Widget _buildOffersSheet(
    Color bg, Color border, Color muted, List<Map<String, dynamic>> offers,
  ) {
    if (offers.isEmpty) {
      return DraggableScrollableSheet(
        initialChildSize: 0.15,
        minChildSize: 0.1,
        maxChildSize: 0.6,
        builder: (_, ctrl) => Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: border)),
          ),
          child: ListView(
            controller: ctrl,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'بانتظار طلبات الركاب…',
                    style: GoogleFonts.ibmPlexSansArabic(color: muted, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.2,
      maxChildSize: 0.8,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: border)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: ctrl,
                padding: const EdgeInsets.all(12),
                itemCount: offers.length,
                itemBuilder: (_, i) => OfferCard(offer: offers[i])
                    .animate()
                    .fade(delay: (50 * i).ms)
                    .slideX(begin: 0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}