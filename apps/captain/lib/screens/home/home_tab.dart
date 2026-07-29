import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';
import 'offer_card.dart';
import 'active_trip_panel.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// The captain's map tab: a glanceable status header, the go-online control,
/// and the offers sheet — all floating over the map owned by MainShell.
///
/// The important change here is that **going online is now a visible, primary
/// control**. It used to be a side effect of tapping the centre nav button,
/// which is undiscoverable: a new captain had no way to learn that the logo
/// button was also the earn/don't-earn switch. Category leaders all give this
/// its own large pill, and so do we now.
///
/// The idle state also does real work instead of showing a bare sentence: it
/// tells the captain whether they are actually reachable (socket status) and
/// what to do next.
class HomeTab extends StatelessWidget {
  const HomeTab({
    super.key,
    required this.mapController,
    required this.online,
    required this.onToggleOnline,
    this.busy = false,
  });

  final MapController mapController;
  final bool online;
  final ValueChanged<bool> onToggleOnline;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final state = context.watch<CaptainState>();

    final approval = state.captain?['approval_status'] ?? state.captain?['status'];
    final isApproved = approval == 'approved';
    final activeTrip = state.activeTrip;
    final offers = state.offers;

    // `name` may be null, empty or whitespace — indexing [0] throws on an
    // empty string, so the initial is derived defensively.
    final rawName = (state.user?['name'] as String?)?.trim();
    final hasName = rawName != null && rawName.isNotEmpty;

    return Stack(
      children: [
        // NOTE: trip markers are rendered by MainShell as children of the real
        // FlutterMap. A MarkerLayer resolves its position via
        // MapCamera.of(context) and throws without a FlutterMap ancestor, so
        // it must never be placed in this plain Stack.
        PositionedDirectional(
          top: MediaQuery.of(context).padding.top + 10,
          start: AppTokens.spaceMd,
          end: AppTokens.spaceMd,
          child: _StatusHeader(
            name: hasName ? rawName : strings.captainFallbackName,
            online: online,
            isApproved: isApproved,
            connected: state.offersWsStatus == 'connected',
          ),
        ),

        if (activeTrip != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: ActiveTripPanel(trip: activeTrip),
          )
        else
          Align(
            alignment: Alignment.bottomCenter,
            child: _OffersSheet(
              offers: offers,
              online: online,
              busy: busy,
              isApproved: isApproved,
              onToggleOnline: onToggleOnline,
            ),
          ),
      ],
    );
  }
}

/// Floating identity + state strip. Reads in one glance: who am I, am I
/// earning, and is my connection actually alive.
class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.name,
    required this.online,
    required this.isApproved,
    required this.connected,
  });

  final String name;
  final bool online;
  final bool isApproved;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final go = GoTheme.of(context);

    final Color stateColor;
    final String stateLabel;
    if (!isApproved) {
      stateColor = AppTokens.warning;
      stateLabel = strings.homeAwaitingApproval;
    } else if (online) {
      stateColor = AppTokens.success;
      stateLabel = strings.homeOnlineReady;
    } else {
      stateColor = go.muted;
      stateLabel = strings.homeOffline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSm,
        vertical: AppTokens.spaceXs + 2,
      ),
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        boxShadow: AppTokens.shadowFloating,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTokens.primary.withOpacity(0.14),
            ),
            alignment: Alignment.center,
            child: Text(
              name.characters.first.toUpperCase(),
              style: AppTokens.font(
                color: AppTokens.primary,
                fontWeight: FontWeight.w900,
                fontSize: 15,
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
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTokens.font(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: go.text,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: stateColor,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        stateLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTokens.font(fontSize: 11.5, color: stateColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Live-connection telltale. When the captain is online but the
          // socket is down they are not actually reachable, and previously
          // nothing said so.
          if (online)
            Tooltip(
              message: connected ? strings.homeSocketLive : strings.homeSocketReconnecting,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 6, end: 4),
                child: Icon(
                  connected
                      ? Icons.wifi_tethering_rounded
                      : Icons.wifi_tethering_off_rounded,
                  size: 19,
                  color: connected ? AppTokens.success : AppTokens.warning,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The bottom sheet. Three distinct states — offline, online-and-waiting, and
/// offers-present — each with a clear next action.
class _OffersSheet extends StatelessWidget {
  const _OffersSheet({
    required this.offers,
    required this.online,
    required this.busy,
    required this.isApproved,
    required this.onToggleOnline,
  });

  final List<Map<String, dynamic>> offers;
  final bool online;
  final bool busy;
  final bool isApproved;
  final ValueChanged<bool> onToggleOnline;

  @override
  Widget build(BuildContext context) {
    // strings is used in _idleBody which re-resolves it; this local was dead.
    final go = GoTheme.of(context);

    // Strict online guard: trip offer cards must NEVER render while the
    // captain is offline. Going offline clears CaptainState.offers, but a
    // captain can still toggle offline with cards briefly in memory, and
    // tapping a stale offer then hits an endpoint that refuses it (403
    // OFFLINE). Gating the whole list on `online` guarantees an offline
    // captain falls through to the idle body — the offline status banner and
    // the go-online control — instead of stale, un-actionable offers.
    final hasOffers = online && offers.isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusXl),
        ),
        boxShadow: AppTokens.shadowSheet,
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.55,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AppTokens.spaceSm),
              _grabHandle(context),
              const SizedBox(height: AppTokens.spaceMd),
              if (hasOffers)
                Flexible(child: _offersList())
              else
                _idleBody(context),
              const SizedBox(height: AppTokens.spaceMd),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grabHandle(BuildContext context) {
    final go = GoTheme.of(context);
    return Container(
      width: 42,
      height: 4,
      decoration: BoxDecoration(
        color: go.border,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      ),
    );
  }

  Widget _offersList() {
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
      itemCount: offers.length,
      // Keyed by trip id: without a key Flutter reuses the State of whichever
      // card previously sat at this index, so an expiring countdown would
      // carry over onto a brand-new offer.
      itemBuilder: (_, i) => OfferCard(
        key: ValueKey(offers[i]['id']),
        offer: offers[i],
      ).animate().fadeIn(delay: (60 * i).ms).slideY(begin: 0.15, end: 0),
    );
  }

  Widget _idleBody(BuildContext context) {
    final strings = AppStrings.of(context);
    final go = GoTheme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        0,
        AppTokens.spaceLg,
        0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (online) ...[
            const _SearchingPulse(),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              strings.homeSearchingTitle,
              style: AppTokens.font(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: go.text,
              ),
            ),
            const SizedBox(height: AppTokens.space2xs),
            Text(
              strings.homeSearchingSubtitle,
              textAlign: TextAlign.center,
              style: AppTokens.font(fontSize: 13, color: go.muted),
            ),
          ] else ...[
            Text(
              isApproved ? strings.homeOfflineTitle : strings.homeUnderReviewTitle,
              style: AppTokens.font(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: go.text,
              ),
            ),
            const SizedBox(height: AppTokens.space2xs),
            Text(
              isApproved
                  ? strings.homeGoOnlineHint
                  : strings.homeApprovalHint,
              textAlign: TextAlign.center,
              style: AppTokens.font(fontSize: 13, color: go.muted),
            ),
          ],
          const SizedBox(height: AppTokens.spaceMd),
          GoOnlineButton(
            online: online,
            busy: busy,
            enabled: isApproved,
            width: double.infinity,
            onChanged: onToggleOnline,
          ),
        ],
      ),
    );
  }
}

/// Concentric expanding rings — the visual language for "listening".
class _SearchingPulse extends StatelessWidget {
  const _SearchingPulse();

  @override
  Widget build(BuildContext context) {
    // go.action so the pulse tracks the brightness-aware action colour
    // (lime on dark, brand-green on light) instead of always being green.
    final go = GoTheme.of(context);
    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: go.action.withOpacity(0.10),
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .scaleXY(begin: 0.6, end: 1, duration: 1600.ms, curve: Curves.easeOut)
              .fadeOut(duration: 1600.ms),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: go.action.withOpacity(0.16),
            ),
            child: Icon(
              Icons.radar_rounded,
              size: 19,
              color: go.action,
            ),
          ),
        ],
      ),
    );
  }
}
