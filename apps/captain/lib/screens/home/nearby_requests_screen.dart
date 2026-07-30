import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:provider/provider.dart';

import '../../models/ride_request_model.dart';
import '../../services/captain_state.dart';
import 'offer_card.dart';

/// **رحلات متاحة** — the standing queue of nearby ride requests.
///
/// Where the map sheet shows one pushed offer at a time under a 15-second
/// timer, this is the browsable list: every open request within radius, with
/// the rider's proposed fare and the same three decisions on each one.
///
/// Two substantive fixes over the previous version:
///
///  * **Accept actually accepts.** The "قبول السعر" button used to POST a
///    *bid* at the rider's own price, which does not assign the trip — it
///    only queues another offer the rider still has to pick. A captain who
///    thought they had the job did not have it. Accepting now goes through
///    `POST /trips/:id/accept`.
///  * **Offline is stated, not implied.** An offline captain got an empty
///    list indistinguishable from "no demand right now", so they waited for
///    work that could never arrive. Being offline now short-circuits the
///    fetch and explains itself, with the fix directly underneath.
///
/// Cards are rendered by the shared [OfferCard] so the fare, the distances
/// and the three actions read identically here and on the map.
class NearbyRequestsScreen extends StatefulWidget {
  const NearbyRequestsScreen({super.key});

  @override
  State<NearbyRequestsScreen> createState() => _NearbyRequestsScreenState();
}

class _NearbyRequestsScreenState extends State<NearbyRequestsScreen> {
  List<RideRequestModel> _requests = [];
  bool _loading = true;
  bool _togglingOnline = false;
  String? _errorMessage;

  /// Search radius in km. inDrive lets the captain tune how far out they want
  /// to hunt; the previous version hardcoded 15, which is too wide in dense
  /// Cairo traffic and too narrow on the outskirts.
  double _radiusKm = 15;
  static const List<double> _radiusOptions = [5, 10, 15, 25, 40];

  /// Dismissed locally, so a refresh does not resurrect a card the captain
  /// just skipped.
  final Set<String> _skipped = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchRequests();
    });
  }

  Future<void> _fetchRequests() async {
    final state = context.read<CaptainState>();
    if (state.token == null) return;

    // Offline captains receive nothing by design — the endpoint returns an
    // empty list anyway, so skip the round-trip and show the reason instead.
    if (!state.online) {
      if (!mounted) return;
      setState(() {
        _requests = [];
        _errorMessage = null;
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final res = await state.apiGet('/captain/nearby-requests?radius=${_radiusKm.round()}');
      if (!mounted) return;

      final list = (res['requests'] as List? ?? [])
          .whereType<Map>()
          .map((item) =>
              RideRequestModel.fromJson(Map<String, dynamic>.from(item)))
          .where((r) => !_skipped.contains(r.id))
          .toList();

      setState(() {
        _requests = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        _loading = false;
      });
    }
  }

  Future<void> _toggleOnline(bool value) async {
    if (_togglingOnline) return;
    setState(() => _togglingOnline = true);

    final state = context.read<CaptainState>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await state.setOnline(value);

    if (!mounted) return;
    setState(() => _togglingOnline = false);

    if (!ok && state.gpsError != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(state.gpsError!),
          backgroundColor: AppTokens.warning,
        ),
      );
      return;
    }
    if (ok && value) await _fetchRequests();
  }

  void _skip(String id) {
    setState(() {
      _skipped.add(id);
      _requests.removeWhere((r) => r.id == id);
    });
  }

  /// `RideRequestModel` → the raw-map shape [OfferCard] reads. The card is
  /// deliberately map-driven so it can render both `/captain/offers` trip
  /// rows and `/captain/nearby-requests` rows without a second widget.
  Map<String, dynamic> _asOffer(RideRequestModel r) => {
        'id': r.id,
        'offered_price': r.offeredPrice,
        'distance_km': r.distanceKm,
        'captain_to_pickup_km': r.captainToPickupKm,
        'pickup_address': r.pickupAddress,
        'dropoff_address': r.dropoffAddress,
        'pickup_lat': r.pickupLat,
        'pickup_lng': r.pickupLng,
        'dropoff_lat': r.dropoffLat,
        'dropoff_lng': r.dropoffLng,
        'rider_name': r.riderName,
        'rider_photo': r.riderAvatar,
      };

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CaptainState>();
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    final approval =
        state.captain?['approval_status'] ?? state.captain?['status'];
    final isApproved = approval == 'approved';

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(
          strings.availableTripsTitle,
          style: AppTokens.font(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: go.text,
          ),
        ),
        backgroundColor: go.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (state.online && _requests.isNotEmpty)
            Center(
              child: Container(
                margin:
                    const EdgeInsetsDirectional.only(end: AppTokens.spaceXs),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: go.action.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: Text(
                  '${_requests.length}',
                  style: AppTokens.money(
                    fontSize: 14,
                    color: go.action,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: strings.refresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _fetchRequests,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _buildBody(state, isApproved),
      ),
    );
  }

  Widget _buildBody(CaptainState state, bool isApproved) {
    final go = GoTheme.of(context);
    // Guard first: nothing below this point is meaningful while offline.
    if (!state.online) {
      return ListView(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        children: [
          const SizedBox(height: AppTokens.spaceLg),
          OfflineGuardBanner(
            online: state.online,
            busy: _togglingOnline,
            isApproved: isApproved,
            onToggleOnline: _toggleOnline,
          ),
        ],
      );
    }

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(AppTokens.spaceMd),
        child: SkeletonList(count: 3, itemHeight: 190),
      );
    }

    if (_errorMessage != null) {
      return ErrorState(message: _errorMessage!, onRetry: _fetchRequests);
    }

    return RefreshIndicator(
      onRefresh: _fetchRequests,
      color: go.action,
      child: _requests.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              children: [
                _buildRadiusSelector(),
                SizedBox(height: MediaQuery.of(context).size.height * 0.06),
                EmptyState(
                  icon: Icons.radar_rounded,
                  title: strings.noOffersNow,
                  subtitle: strings.nearbyEmptySubtitle,
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceMd,
                AppTokens.spaceMd,
                AppTokens.spaceMd,
                AppTokens.spaceLg,
              ),
              itemCount: _requests.length + 1,
              itemBuilder: (_, i) {
                if (i == 0) return _buildRadiusSelector();
                final req = _requests[i - 1];
                return OfferCard(
                  key: ValueKey(req.id),
                  offer: _asOffer(req),
                  // A browsable queue must not expire cards as the captain
                  // scrolls; the timer belongs to pushed offers only.
                  showCountdown: false,
                  onDismissed: _skip,
                ).animate().fadeIn(delay: (50 * i).ms).slideY(
                      begin: 0.12,
                      end: 0,
                      curve: Curves.easeOut,
                    );
              },
            ),
    );
  }

  /// inDrive-style radius chips: the captain tunes how far out they want to
  /// hunt for work, and the list refetches immediately. Kept above the cards
  /// so it is reachable without scrolling to a settings page.
  Widget _buildRadiusSelector() {
    final go = GoTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      child: Row(
        children: [
          Icon(Icons.radar_rounded, size: 18, color: go.muted),
          const SizedBox(width: AppTokens.spaceSm),
          Text(
            AppStrings.of(context).searchRadiusLabel,
            style: AppTokens.font(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: go.muted,
            ),
          ),
          const SizedBox(width: AppTokens.spaceMd),
          Expanded(
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _radiusOptions.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppTokens.spaceXs),
                itemBuilder: (_, i) {
                  final km = _radiusOptions[i];
                  final selected = km == _radiusKm;
                  return ChoiceChip(
                    label: Text(AppStrings.of(context).radiusKm(km.round())),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _radiusKm = km);
                      _fetchRequests();
                    },
                    labelStyle: AppTokens.font(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      // go.onAction: black on lime in dark mode — white-on-lime
                      // is ~1.8:1 contrast (near-illegible).
                      color: selected ? go.onAction : go.text,
                    ),
                    selectedColor: go.action,
                    backgroundColor: go.surface,
                    side: BorderSide(
                      color: selected ? go.action : go.border,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
