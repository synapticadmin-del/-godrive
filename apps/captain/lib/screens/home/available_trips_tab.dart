import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:provider/provider.dart';
import 'package:tempo_captain/services/captain_state.dart';

import 'offer_card.dart';
import 'offer_card_entrance.dart';

/// "رحلات متاحة" — every live nearby request in one scrollable list.
///
/// The map sheet on the home tab only has room for whatever fits above the
/// fold, and it competes with the map for attention. This tab is the opposite
/// trade: no map, full height, all of the work that is currently on offer,
/// so a captain deciding what to take next can actually compare options.
///
/// Two things it deliberately does NOT do:
///
///  * It does not fetch on its own timer. `CaptainState` already polls
///    `/captain/offers` every 20s and pushes on the `trip.offer` WebSocket
///    event, so a second poller here would double the request rate and let
///    the two lists disagree. It renders `state.offers` and adds a pull to
///    refresh for impatience.
///  * It does not show anything at all while the captain is offline. The
///    server does not filter offers by `is_online`, so the list would
///    otherwise stay full of tappable work after clocking off.
class AvailableTripsTab extends StatelessWidget {
  const AvailableTripsTab({
    super.key,
    required this.online,
    required this.onToggleOnline,
    this.busy = false,
  });

  final bool online;
  final ValueChanged<bool> onToggleOnline;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CaptainState>();
    final go = GoTheme.of(context);

    final approval =
        state.captain?['approval_status'] ?? state.captain?['status'];
    final isApproved = approval == 'approved';
    final offers = state.offers;

    return Scaffold(
      // Transparent so the IndexedStack in MainShell can keep the map alive
      // at index 0 while this tab is on top; the opaque fill below covers it.
      backgroundColor: Colors.transparent,
      body: Container(
        color: go.bg,
        child: Column(
          children: [
            _Header(
              count: online ? offers.length : null,
              online: online,
              connected: state.offersWsStatus == 'connected',
            ),
            Expanded(
              child: !online
                  ? OfflineTripsPlaceholder(
                      online: online,
                      busy: busy,
                      enabled: isApproved,
                      onToggleOnline: onToggleOnline,
                      title: isApproved
                          ? AppStrings.of(context).offlineTripsTitle
                          : null,
                      message: isApproved
                          ? AppStrings.of(context).offlineTripsMessage
                          : null,
                    )
                  : _OffersBody(offers: offers, error: state.error),
            ),
          ],
        ),
      ),
    );
  }
}

class _OffersBody extends StatelessWidget {
  const _OffersBody({required this.offers, this.error});

  final List<Map<String, dynamic>> offers;
  final String? error;

  Future<void> _refresh(BuildContext context) =>
      context.read<CaptainState>().refreshOffers();

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    if (offers.isEmpty && error != null) {
      return ErrorState(message: error!, onRetry: () => _refresh(context));
    }

    return RefreshIndicator(
      color: go.action,
      onRefresh: () => _refresh(context),
      child: offers.isEmpty
          ? const _WaitingForOffers()
          : ListView.builder(
              padding: kOfferListPadding,
              itemCount: offers.length,
              // Keyed by trip id so an expiring countdown never carries over
              // onto a different offer when the list reorders.
              itemBuilder: (_, i) => OfferCardEntrance(
                index: i,
                child: OfferCard(
                  key: ValueKey(offers[i]['id']),
                  offer: offers[i],
                ),
              ),
            ),
    );
  }
}

/// Online, reachable, nothing on offer yet. Scrollable so pull to refresh
/// still works on an otherwise empty screen.
class _WaitingForOffers extends StatelessWidget {
  const _WaitingForOffers();

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceXl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTokens.primary.withOpacity(0.10),
                    ),
                    child: const Icon(
                      Icons.radar_rounded,
                      size: 38,
                      color: AppTokens.primary,
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleXY(
                        begin: 0.92,
                        end: 1.04,
                        duration: 1500.ms,
                        curve: Curves.easeInOut,
                      ),
                  const SizedBox(height: AppTokens.spaceMd),
                  Text(
                    AppStrings.of(context).noOffersNow,
                    style: AppTokens.font(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: go.text,
                    ),
                  ),
                  const SizedBox(height: AppTokens.space2xs),
                  Text(
                    AppStrings.of(context).searchingConstantly,
                    textAlign: TextAlign.center,
                    style: AppTokens.font(
                      fontSize: 13,
                      color: go.muted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Title, live count, and a connection telltale.
///
/// The telltale matters here more than anywhere else in the app: this screen
/// is a list of live work, so "empty" is only trustworthy if the socket is
/// actually up. Without it an empty list is ambiguous between "no demand" and
/// "you are not receiving anything".
class _Header extends StatelessWidget {
  const _Header({
    required this.count,
    required this.online,
    required this.connected,
  });

  /// Null while offline, when a count would be meaningless.
  final int? count;
  final bool online;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);
    final n = count;

    return Container(
      padding: EdgeInsetsDirectional.only(
        start: AppTokens.spaceMd,
        end: AppTokens.spaceMd,
        top: MediaQuery.of(context).padding.top + AppTokens.spaceMd,
        bottom: AppTokens.spaceMd,
      ),
      decoration: BoxDecoration(
        color: go.panel,
        border: Border(bottom: BorderSide(color: go.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.availableTripsTitle,
                  style: AppTokens.font(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: go.text,
                  ),
                ),
                if (n != null) ...[
                  const SizedBox(height: AppTokens.space2xs),
                  Text(
                    n == 0
                        ? strings.noRequestsNow
                        : strings.requestsNearbyCount(n),
                    style: AppTokens.font(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: go.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (online)
            Tooltip(
              message: connected ? strings.homeSocketLive : strings.homeSocketReconnecting,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceXs,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: (connected ? AppTokens.success : AppTokens.warning)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      connected
                          ? Icons.wifi_tethering_rounded
                          : Icons.wifi_tethering_off_rounded,
                      size: 15,
                      color:
                          connected ? AppTokens.success : AppTokens.warning,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      connected ? strings.liveConnected : strings.liveConnecting,
                      style: AppTokens.font(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: connected
                            ? AppTokens.success
                            : AppTokens.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
