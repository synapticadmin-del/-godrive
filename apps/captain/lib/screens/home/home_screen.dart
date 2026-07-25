import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';
import 'package:synaptic_go_captain/screens/documents/document_upload_screen.dart';
import 'package:synaptic_go_captain/screens/earnings/earnings_screen.dart';
import 'package:synaptic_go_captain/screens/profile/settings_screen.dart';
import 'package:synaptic_go_captain/screens/safety/sos_screen.dart';
import 'offer_card.dart';
import 'active_trip_panel.dart';
import 'package:flutter_animate/flutter_animate.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<CaptainState>();
      state.refreshMe();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CaptainState>();
    final approval = state.captain?['approval_status'] ?? state.captain?['status'];
    final isApproved = approval == 'approved';
    final activeTrip = state.activeTrip;
    final offers = state.offers;

    return Scaffold(
      backgroundColor: AppTokens.lightBg,
      body: Stack(
        children: [
          // RepaintBoundary isolates live map rendering GPU calls from top bar and bottom sheet animations
          RepaintBoundary(
            child: FlutterMap(
              mapController: _mapController,
              options: const MapOptions(
                initialCenter: LatLng(30.0444, 31.2357),
                initialZoom: 14.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                ),
                if (activeTrip != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(activeTrip['pickup_lat'], activeTrip['pickup_lng']),
                        child: const Icon(Icons.location_on, color: AppTokens.primary, size: 40),
                      ),
                      if (activeTrip['dropoff_lat'] != null)
                        Marker(
                          point: LatLng(activeTrip['dropoff_lat'], activeTrip['dropoff_lng']),
                          child: const Icon(Icons.flag, color: AppTokens.accent, size: 40),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(context, state, isApproved),
                if (!isApproved) _buildApprovalBanner(context),
              ],
            ),
          ),

          if (activeTrip != null)
            Positioned(
              left: 16,
              top: 120,
              child: FloatingActionButton(
                heroTag: 'sos_fab',
                backgroundColor: AppTokens.danger,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SosScreen())),
                child: const Icon(Icons.sos, color: Colors.white),
              ).animate().scale().shake(),
            ),

          Align(
            alignment: Alignment.bottomCenter,
            child: activeTrip != null
                ? ActiveTripPanel(trip: activeTrip)
                : _buildOffersSheet(context, offers),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, CaptainState state, bool isApproved) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTokens.lightPanel.withOpacity(0.85),
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: AppTokens.lightBorder.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
          )
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppTokens.primary.withOpacity(0.2),
            child: Text(
              state.user?['name']?.substring(0, 1) ?? 'C',
              style: const TextStyle(color: AppTokens.primary, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.user?['name'] ?? 'كابتن',
                  style: const TextStyle(color: AppTokens.lightText, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: state.offersWsStatus == 'connected' ? AppTokens.success : AppTokens.danger,
                      ),
                    ).animate(onPlay: (c) => c.repeat()).fade(duration: 1.seconds),
                    const SizedBox(width: 4),
                    Text(
                      isApproved ? (state.online ? 'متصل الآن' : 'غير متصل') : 'بانتظار الموافقة',
                      style: TextStyle(
                        color: isApproved ? (state.online ? AppTokens.success : AppTokens.lightMuted) : AppTokens.accent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isApproved)
            Switch(
              value: state.online,
              activeColor: AppTokens.success,
              onChanged: (val) => state.setOnline(val),
            ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet, color: AppTokens.lightText),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EarningsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: AppTokens.lightText),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalBanner(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DocumentUploadScreen())),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTokens.accent.withOpacity(0.2),
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(color: AppTokens.accent.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTokens.accent),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'حسابك قيد المراجعة. يرجى رفع المستندات المطلوبة لتفعيل الحساب.',
                style: TextStyle(color: AppTokens.accent, fontSize: 13),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTokens.accent),
          ],
        ),
      ).animate().fade().slideY(begin: -0.2),
    );
  }

  Widget _buildOffersSheet(BuildContext context, List<Map<String, dynamic>> offers) {
    if (offers.isEmpty) return const SizedBox.shrink();
    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.2,
      maxChildSize: 0.8,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTokens.lightPanel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTokens.radiusXl)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, -5)),
            ],
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTokens.lightBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: offers.length,
                  itemBuilder: (context, index) {
                    return OfferCard(offer: offers[index])
                        .animate()
                        .fade(delay: (50 * index).ms)
                        .slideX(begin: 0.2);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
