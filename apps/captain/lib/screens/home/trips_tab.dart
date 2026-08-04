import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:tempo_captain/services/captain_state.dart';

/// Captain's trip history tab — list of all completed and active trips.
///
/// This sits inside an IndexedStack at index 1, directly above the map tile
/// layer. The Scaffold is kept transparent so the IndexedStack's map child (at
/// index 0) can be retained in the widget tree when the captain switches tabs —
/// it just stays hidden behind this screen. Because the map tiles are visible
/// through a transparent background, every content region gets an explicit
/// opaque backdrop using the theme background colour.
///
/// Freshness: the list used to load once in `initState` and then sit stale
/// until a manual pull-to-refresh, so a trip the captain had just completed
/// stayed missing from the history — the "رحلاتي مش بيتحدث" complaint. Two
/// triggers now keep it current:
///  * any event on the live trip socket (a completion broadcasts
///    `trip.updated` the moment the row flips), and
///  * `CaptainState` clearing `activeTrip` — the client-side signal that
///    the captain's trip just ended (complete or rider-cancel).
///
/// All copy is read from [AppStrings] (resolved from the ambient locale) so
/// this file carries no inline Arabic literals — see `app_strings.dart`.
class TripsTab extends StatefulWidget {
  const TripsTab({super.key});

  @override
  State<TripsTab> createState() => _TripsTabState();
}

class _TripsTabState extends State<TripsTab> {
  List<Map<String, dynamic>> _trips = [];
  bool _loading = true;
  String? _error;

  StreamSubscription<Map<String, dynamic>>? _tripEventsSub;

  /// The trip id the list currently treats as in-flight. When CaptainState
  /// drops it (completion/cancel pushed the trip out), the history is stale
  /// and reloads — without waiting for the captain to pull-to-refresh.
  String? _watchedTripId;

  @override
  void initState() {
    super.initState();
    _load();

    final state = context.read<CaptainState>();
    _watchedTripId = state.activeTrip?['id'] as String?;

    // Any room event (completion, cancellation, a status flip) means the
    // history behind this tab is older than the server's truth.
    _tripEventsSub = state.activeTripWsMessages.listen((ev) {
      if (!mounted) return;
      if (ev['type'] == 'trip.updated') _load();
    });

    state.addListener(_onCaptainStateChanged);
  }

  @override
  void dispose() {
    _tripEventsSub?.cancel();
    context.read<CaptainState>().removeListener(_onCaptainStateChanged);
    super.dispose();
  }

  void _onCaptainStateChanged() {
    if (!mounted) return;
    final state = context.read<CaptainState>();
    final currentId = state.activeTrip?['id'] as String?;
    if (_watchedTripId != null && currentId == null) {
      // The trip just left the captain's hands — reload so the completed
      // (or cancelled) row appears immediately.
      _watchedTripId = null;
      _load();
    } else {
      _watchedTripId = currentId;
    }
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
      // Only trips assigned to this captain — the server returns all trips the
      // authenticated user can see, which may include archived or admin rows.
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
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    return Scaffold(
      // Transparent so the IndexedStack retains the map widget on tab 0.
      backgroundColor: Colors.transparent,
      body: Container(
        // Opaque fill that covers the map tiles underneath — without this,
        // list text would be illegible against the satellite/street imagery.
        color: go.bg,
        child: Column(
          children: [
            _TripsHeader(
              tripCount: _loading ? null : _trips.length,
            ),
            Expanded(
              child: _loading
                  ? const SkeletonList(count: 6)
                  : _error != null
                      ? ErrorState(message: _error!, onRetry: _load)
                      : _trips.isEmpty
                          ? EmptyState(
                              icon: Icons.route_outlined,
                              title: strings.noTripsYet,
                              subtitle: strings.noTripsYetSubtitle,
                            )
                          : RefreshIndicator(
                              color: go.action,
                              onRefresh: _load,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  AppTokens.spaceMd,
                                  AppTokens.spaceXs,
                                  AppTokens.spaceMd,
                                  AppTokens.space2xl,
                                ),
                                itemCount: _trips.length,
                                itemBuilder: (_, i) => _TripCard(
                                  trip: _trips[i],
                                ),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Screen header with a title and a lightweight trip-count summary.
///
/// The count is omitted during loading and while the list is empty — the
/// skeleton / empty-state widgets communicate that state themselves.
class _TripsHeader extends StatelessWidget {
  const _TripsHeader({
    required this.tripCount,
  });

  /// null while loading so the summary line stays hidden.
  final int? tripCount;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    return Container(
      color: go.panel,
      padding: EdgeInsetsDirectional.only(
        start: AppTokens.spaceMd,
        end: AppTokens.spaceMd,
        top: MediaQuery.of(context).padding.top + AppTokens.spaceMd,
        bottom: AppTokens.spaceMd,
      ),
      decoration: BoxDecoration(
        color: go.panel,
        border: Border(
          bottom: BorderSide(color: go.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.tripsTabTitle,
            textAlign: TextAlign.start,
            style: AppTokens.font(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: go.text,
            ),
          ),
          if (tripCount != null) ...[
            const SizedBox(height: AppTokens.space2xs),
            Text(
              // Gives the captain a quick count at a glance — derived entirely
              // from already-loaded data, no extra network call.
              strings.tripsRecorded(tripCount!),
              style: AppTokens.font(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: go.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
  });

  final Map<String, dynamic> trip;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    final status = trip['status'] as String? ?? '';

    // A completed trip's real payout is final_fare; estimated_fare is only the
    // pre-trip quote, so showing it made finished trips display the wrong
    // amount whenever the fare was adjusted on completion.
    final fare = (trip['final_fare'] as num?)?.toDouble() ??
        (trip['estimated_fare'] as num?)?.toDouble() ??
        0;

    final pickup = (trip['pickup_address'] as String?)?.trim();
    final dropoff = (trip['dropoff_address'] as String?)?.trim();

    // substring(0, 10) throws on any timestamp shorter than 10 characters —
    // guard defensively rather than assume ISO-8601 from the server.
    final rawDate = (trip['created_at'] ?? '').toString();
    final date = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: go.border, width: 1),
        boxShadow: AppTokens.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: status chip on the trailing side, fare on the leading.
            // Fare leads because it is the most decision-relevant fact on a
            // history card — the captain scans earnings, not labels.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Fare — oversized numeral so it reads at arm's length.
                Text(
                  fare.toStringAsFixed(0),
                  style: AppTokens.money(
                    fontSize: 22,
                    color: AppTokens.primary,
                  ),
                ),
                const SizedBox(width: AppTokens.space2xs),
                Text(
                  strings.egp,
                  style: AppTokens.font(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.primary,
                  ),
                ),
                const Spacer(),
                StatusChip(
                  label: strings.statusLabel(status),
                  variant: _statusVariant(status),
                ),
              ],
            ),

            const SizedBox(height: AppTokens.spaceMd),

            // Route — dot + connector idiom mirrors offer_card.dart so the
            // captain reads the same visual language across the product.
            _buildRoute(
              pickup: (pickup == null || pickup.isEmpty) ? strings.unknownPickup : pickup,
              dropoff: (dropoff == null || dropoff.isEmpty) ? strings.unknownDropoff : dropoff,
              go: go,
              strings: strings,
            ),

            const SizedBox(height: AppTokens.spaceSm),

            // Date — quiet footer, smaller than the route text.
            Text(
              date,
              style: AppTokens.font(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: go.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoute({
    required String pickup,
    required String dropoff,
    required GoTheme go,
    required AppStrings strings,
  }) {
    return Column(
      children: [
        _addressRow(
          dotColor: AppTokens.primary,
          label: strings.fromLabel,
          value: pickup,
          go: go,
        ),
        // Vertical connector inset to sit directly under the dot centre.
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 5),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              width: 2,
              height: 14,
              color: go.border,
            ),
          ),
        ),
        _addressRow(
          dotColor: AppTokens.danger,
          label: strings.toLabel,
          value: dropoff,
          go: go,
        ),
      ],
    );
  }

  Widget _addressRow({
    required Color dotColor,
    required String label,
    required String value,
    required GoTheme go,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor.withOpacity(0.18),
              border: Border.all(color: dotColor, width: 2.5),
            ),
          ),
        ),
        const SizedBox(width: AppTokens.spaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTokens.font(fontSize: 11, color: go.muted),
              ),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTokens.font(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: go.text,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  StatusVariant _statusVariant(String s) {
    switch (s) {
      case 'completed':
        return StatusVariant.success;
      case 'in_progress':
      case 'assigned':
      case 'arrived':
        return StatusVariant.info;
      case 'cancelled':
        return StatusVariant.danger;
      default:
        return StatusVariant.neutral;
    }
  }
}
