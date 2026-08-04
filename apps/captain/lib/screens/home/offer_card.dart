import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:tempo_captain/services/captain_state.dart';

/// An incoming ride offer.
///
/// This is the single highest-stakes card in the product: the captain decides
/// on it in a couple of seconds, often at a traffic light. The redesign makes
/// the decision inputs unmissable in priority order —
///
///   1. **the rider**, with their photo and name, because this is who the
///      captain is agreeing to pick up;
///   2. **the fare**, as an oversized numeral, because that is the decision;
///   3. **how far away the pickup is**, because that is the cost of taking it;
///   4. the route itself;
///   5. the actions.
///
/// The card is a frosted-glass sheet (BackDropFilter) so the map stays
/// visible beneath it, and it is deliberately more compact than the previous
/// solid panel — the captain sees the road and the offer at the same time.
///
/// It also fixes two real defects in the previous version:
///
///  * The header packed a title, two distance labels and the fare into one
///    `spaceBetween` Row, which overflowed on small screens whenever an
///    address-derived label ran long. Layout is now a resilient stack.
///  * The countdown ran to zero and then simply stopped, leaving a dead card
///    on screen claiming to be actionable. Expiry now actively withdraws the
///    offer.
///
/// The card offers three ways out, because a fixed-price accept/reject pair
/// throws away the negotiation the marketplace is built on: **accept the
/// rider's fare**, **decline**, or **counter with your own price**. The
/// counter-offer posts a bid and leaves the trip in play — the rider still
/// has to choose it — so the card reports "bid sent" rather than vanishing.
///
/// All copy is read from [AppStrings] (resolved from the ambient locale) so
/// this file carries no inline Arabic literals — see `app_strings.dart`.
class OfferCard extends StatefulWidget {
  const OfferCard({
    super.key,
    required this.offer,
    this.showCountdown = true,
    this.onDismissed,
  });

  final Map<String, dynamic> offer;

  /// The map sheet surfaces live pushes where the 15s window is the point.
  /// The "Available Trips" list shows the standing queue, where a countdown
  /// would expire every card the captain scrolled past.
  final bool showCountdown;

  /// Lets a host list drop the card from its own collection on decline.
  final ValueChanged<String>? onDismissed;

  @override
  State<OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<OfferCard>
    with SingleTickerProviderStateMixin {
  static const _window = 15;

  late final AnimationController _countdown = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _window),
  );

  Timer? _hapticTimer;
  bool _accepting = false;
  bool _bidding = false;
  bool _expired = false;
  int _lastWholeSecond = _window;

  /// Set once the captain's counter-offer is accepted by the server. The trip
  /// is still open — the rider chooses — so the card stays, but it must stop
  /// inviting a second identical bid.
  double? _bidSent;

  bool get _busy => _accepting || _bidding;

  int get _secondsLeft => (_window * (1 - _countdown.value)).ceil();

  @override
  void initState() {
    super.initState();

    final id = widget.offer['id'];
    if (id is String) {
      _bidSent = context.read<CaptainState>().bidFor(id);
    }

    if (!widget.showCountdown) return;

    _countdown.forward();
    _countdown.addStatusListener(_onCountdownStatus);

    // Haptic ticks in the final five seconds, driven off wall-clock rather
    // than a rebuild, so the pulse stays steady regardless of frame timing.
    _hapticTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = _secondsLeft;
      if (left != _lastWholeSecond) {
        _lastWholeSecond = left;
        if (left > 0 && left <= 5) HapticFeedback.lightImpact();
      }
    });
  }

  void _onCountdownStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted || _expired) return;
    setState(() => _expired = true);
    // An offer nobody acted on is gone. Tell the server so it can re-offer,
    // instead of leaving a stale card that fails on tap.
    final id = widget.offer['id'];
    if (id is String) {
      context.read<CaptainState>().decline(id);
    }
  }

  @override
  void dispose() {
    _hapticTimer?.cancel();
    _countdown.removeStatusListener(_onCountdownStatus);
    _countdown.dispose();
    super.dispose();
  }

  /// **1. قبول بالسعر الحالي** — take the rider's fare as offered.
  /// `POST /trips/:id/accept` assigns the trip outright.
  Future<void> _accept() async {
    if (_busy || _expired) return;
    setState(() => _accepting = true);
    HapticFeedback.mediumImpact();
    _countdown.stop();

    final state = context.read<CaptainState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await state.accept(widget.offer['id'] as String);
    } catch (e) {
      if (!mounted) return;
      setState(() => _accepting = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception:', '').trim()),
          backgroundColor: AppTokens.danger,
        ),
      );
      // Accepting can lose a race (409 TRIP_TAKEN) — refresh so the card goes
      // away rather than inviting another doomed tap.
      await state.refreshOffers();
    }
  }

  /// **2. رفض / تخطي الرحلة** — dismiss the card locally. There is no
  /// server-side decline: the trip simply stays available to other captains.
  void _decline() {
    if (_busy) return;
    HapticFeedback.lightImpact();
    _countdown.stop();
    final id = widget.offer['id'];
    if (id is String) {
      context.read<CaptainState>().decline(id);
      widget.onDismissed?.call(id);
    }
  }

  /// **3. إرسال سعر معدل للعميل** — counter-offer.
  ///
  /// Opens the increment picker, then `POST /trips/:id/bid` with
  /// `{counterPrice}`. The trip is *not* assigned — the rider still chooses —
  /// so the card stays put and switches to a "bid sent" state rather than
  /// disappearing and leaving the captain unsure whether it went through.
  Future<void> _counterOffer() async {
    if (_busy || _expired) return;

    final id = widget.offer['id'];
    if (id is! String) return;

    // The countdown must not expire the card out from under an open sheet.
    _countdown.stop();

    final state = context.read<CaptainState>();
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppStrings.of(context);

    final amount = await CounterOfferSheet.show(
      context,
      offeredPrice: _fare,
    );
    if (amount == null || !mounted) return;

    setState(() => _bidding = true);
    HapticFeedback.mediumImpact();

    try {
      await state.submitBid(id, amount);
      if (!mounted) return;
      setState(() {
        _bidding = false;
        _bidSent = amount;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(strings.bidSentToast(amount.toStringAsFixed(0))),
          backgroundColor: AppTokens.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _bidding = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception:', '').trim()),
          backgroundColor: AppTokens.danger,
        ),
      );
    }
  }

  // ---------------------------------------------------------------
  // Data access
  // ---------------------------------------------------------------

  /// The number the captain is deciding on.
  ///
  /// In a bidding marketplace that is the rider's own proposal
  /// (`offered_price`), not the system estimate — showing the estimate while
  /// accepting the proposal would quote one fare and pay another. The
  /// estimate remains the fallback for trips created outside bidding mode.
  double get _fare =>
      (widget.offer['offered_price'] as num?)?.toDouble() ??
      (widget.offer['offeredPrice'] as num?)?.toDouble() ??
      (widget.offer['estimated_fare'] as num?)?.toDouble() ??
      0;

  /// Whether [_fare] is the rider's own proposal or a system estimate we fell
  /// back to. Legacy trips and any created before bidding shipped carry no
  /// offered_price; showing the estimate is fine, but labelling it as the
  /// rider's number would quote the captain a figure nobody actually proposed.
  bool get _fareIsRiderOffer =>
      (widget.offer['offered_price'] as num?) != null ||
      (widget.offer['offeredPrice'] as num?) != null;

  /// `/captain/offers` returns raw snake_case trip rows, so trip length is
  /// `distance_km`; the camelCase form only appears on the WebSocket payload.
  double? get _tripKm =>
      (widget.offer['distance_km'] as num?)?.toDouble() ??
      (widget.offer['distanceKm'] as num?)?.toDouble();

  /// Only present on `/captain/nearby-requests`.
  double? get _pickupKm =>
      (widget.offer['captain_to_pickup_km'] as num?)?.toDouble();

  int? get _durationMin {
    final raw = (widget.offer['duration_min'] ?? widget.offer['eta_min']) as num?;
    if (raw != null) return raw.toInt();
    // Cairo traffic averages roughly 20 km/h door to door; a rough estimate
    // beats showing the captain nothing at all.
    final km = _tripKm;
    return km == null ? null : math.max(1, (km * 3).round());
  }

  String? get _riderName {
    final raw = widget.offer['rider_name']?.toString().trim();
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  String? get _riderPhoto {
    final raw = widget.offer['rider_photo']?.toString().trim();
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);

    return AnimatedBuilder(
      animation: _countdown,
      builder: (context, _) {
        final urgent =
            widget.showCountdown && _secondsLeft <= 5 && !_expired;
        // go.action for the normal accent so the ring/avatar tint is
        // brightness-aware (lime on dark, green on light); danger overrides
        // at urgency regardless of brightness.
        final accent = urgent ? AppTokens.danger : go.action;

        return Opacity(
          opacity: _expired ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  decoration: BoxDecoration(
                    color: go.isDark
                        ? go.panel.withOpacity(0.72)
                        : go.panel.withOpacity(0.82),
                    borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                    border: Border.all(
                      color: urgent
                          ? AppTokens.danger.withOpacity(0.55)
                          : go.isDark
                              ? Colors.white.withOpacity(0.14)
                              : Colors.white.withOpacity(0.65),
                      width: urgent ? 1.5 : 1,
                    ),
                    boxShadow: AppTokens.shadowOffer,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(go, accent, urgent),
                      _buildMetaStrip(go),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTokens.spaceMd,
                          0,
                          AppTokens.spaceMd,
                          AppTokens.spaceSm,
                        ),
                        child: Column(
                          children: [
                            _buildRoute(go),
                            const SizedBox(height: AppTokens.spaceSm),
                            _buildActions(go),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Rider identity + fare, side by side. The rider's photo and name come
  /// first because the captain is deciding to pick up a person, not a number;
  /// the fare follows at a slightly smaller scale than before so the whole
  /// header stays compact.
  Widget _buildHeader(GoTheme go, Color accent, bool urgent) {
    final strings = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceMd,
        AppTokens.spaceSm,
        AppTokens.spaceMd,
        AppTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        // go.action tint so the header gradient uses the brightness-aware
        // colour (lime on dark, green on light) instead of always being green.
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            go.action.withOpacity(go.isDark ? 0.16 : 0.10),
            go.action.withOpacity(0.03),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Rider avatar + name. The photo comes from the offer payload when
          // the backend includes one; otherwise a branded initial keeps the
          // slot from collapsing.
          _RiderAvatar(
            name: _riderName,
            photoUrl: _riderPhoto,
            accent: accent,
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _expired
                      ? strings.offerExpired
                      : (_fareIsRiderOffer
                          ? strings.riderOfferedPrice
                          : strings.estimatedPrice),
                  style: AppTokens.font(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _expired ? AppTokens.danger : go.muted,
                  ),
                ),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _fare.toStringAsFixed(0),
                        style: AppTokens.money(
                          fontSize: 30,
                          color: go.action,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        strings.egp,
                        style: AppTokens.font(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: go.action,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_riderName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      _riderName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTokens.font(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: go.text,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.showCountdown) ...[
            const SizedBox(width: AppTokens.spaceSm),
            _CountdownRing(
              progress: 1 - _countdown.value,
              seconds: _expired ? 0 : _secondsLeft,
              color: accent,
              urgent: urgent,
            ),
          ],
        ],
      ),
    );
  }

  /// Distance / duration facts as chips — wrapping, so a long value can never
  /// blow out the row the way the old single-line header did.
  Widget _buildMetaStrip(GoTheme go) {
    final strings = AppStrings.of(context);
    final chips = <Widget>[
      if (_pickupKm != null)
        _MetaChip(
          icon: Icons.near_me_rounded,
          label: strings.pickupDistanceKm(_pickupKm!.toStringAsFixed(1)),
          tone: AppTokens.accent,
          border: go.border,
        ),
      if (_tripKm != null)
        _MetaChip(
          icon: Icons.straighten_rounded,
          label: strings.tripDistanceKm(_tripKm!.toStringAsFixed(1)),
          tone: go.muted,
          border: go.border,
        ),
      if (_durationMin != null)
        _MetaChip(
          icon: Icons.schedule_rounded,
          label: strings.aboutMinutes(_durationMin!),
          tone: go.muted,
          border: go.border,
        ),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceMd,
        0,
        AppTokens.spaceMd,
        AppTokens.spaceXs,
      ),
      child: Wrap(spacing: AppTokens.spaceXs, runSpacing: 6, children: chips),
    );
  }

  Widget _buildRoute(GoTheme go) {
    final strings = AppStrings.of(context);
    final pickup = widget.offer['pickup_address']?.toString().trim();
    final dropoff = widget.offer['dropoff_address']?.toString().trim();

    return Column(
      children: [
        _addressRow(
          dotColor: AppTokens.primary,
          label: strings.fromLabel,
          value: (pickup == null || pickup.isEmpty) ? strings.pickupPoint : pickup,
          text: go.text,
          muted: go.muted,
        ),
        // Connector, inset to sit under the dot in both text directions.
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 5),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              width: 2,
              height: 12,
              color: go.border,
            ),
          ),
        ),
        _addressRow(
          dotColor: AppTokens.danger,
          label: strings.toLabel,
          value: (dropoff == null || dropoff.isEmpty) ? strings.destinationPoint : dropoff,
          text: go.text,
          muted: go.muted,
        ),
      ],
    );
  }

  Widget _addressRow({
    required Color dotColor,
    required String label,
    required String value,
    required Color text,
    required Color muted,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor.withOpacity(0.2),
              border: Border.all(color: dotColor, width: 2),
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
                style: AppTokens.font(fontSize: 10.5, color: muted),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTokens.font(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: text,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The three ways out of this card, ranked by how often they are used.
  ///
  /// Accept-at-the-offered-price is the full-width primary because it is the
  /// common case and the one that must survive a glance in traffic — and it
  /// carries the fare in its own label, so the captain confirms the number
  /// they are agreeing to without looking back up at the header. Counter and
  /// decline share the row beneath it: counter is the emphasised secondary,
  /// decline is deliberately the quietest thing on the card.
  Widget _buildActions(GoTheme go) {
    final strings = AppStrings.of(context);
    final disabled = _busy || _expired;

    if (_bidSent != null) return _buildBidSentState(go);

    return Column(
      children: [
        SizedBox(
          height: 46,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: disabled ? null : _accept,
            style: ElevatedButton.styleFrom(
              backgroundColor: go.action,
              foregroundColor: go.onAction,
              disabledBackgroundColor: go.action.withOpacity(0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              ),
            ),
            child: _accepting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: go.onAction,
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 19),
                        const SizedBox(width: AppTokens.spaceXs),
                        Text(
                          strings.acceptWithFare(_fare.toStringAsFixed(0)),
                          style: AppTokens.font(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: go.onAction,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: AppTokens.spaceXs),
        Row(
          children: [
            Expanded(
              flex: 5,
              child: SizedBox(
                height: 42,
                child: OutlinedButton(
                  onPressed: disabled ? null : _counterOffer,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: go.action,
                    side: BorderSide(
                      color: disabled
                          ? go.border
                          : go.action.withOpacity(0.55),
                      width: 1.3,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    ),
                  ),
                  child: _bidding
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: go.action,
                          ),
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.price_change_rounded, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                strings.counterOffer,
                                style: AppTokens.font(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: go.action,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: AppTokens.spaceXs),
            Expanded(
              flex: 3,
              child: SizedBox(
                height: 42,
                child: TextButton(
                  onPressed: disabled ? null : _decline,
                  style: TextButton.styleFrom(
                    foregroundColor: go.muted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      side: BorderSide(color: go.border),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close_rounded, size: 17, color: go.muted),
                        const SizedBox(width: 5),
                        Text(
                          strings.skipLabel,
                          style: AppTokens.font(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: go.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// After a counter-offer the ball is in the rider's court. The card reports
  /// the pending bid and keeps only the two moves that still make sense:
  /// fall back to the original fare, or walk away.
  Widget _buildBidSentState(GoTheme go) {
    final strings = AppStrings.of(context);
    final amount = _bidSent!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceSm,
            vertical: AppTokens.spaceXs,
          ),
          decoration: BoxDecoration(
            color: AppTokens.success.withOpacity(0.12),
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            border: Border.all(color: AppTokens.success.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.hourglass_top_rounded,
                size: 18,
                color: AppTokens.success,
              ),
              const SizedBox(width: AppTokens.spaceXs),
              Expanded(
                child: Text(
                  strings.bidSentBanner(amount.toStringAsFixed(0)),
                  style: AppTokens.font(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.success,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.spaceXs),
        Row(
          children: [
            Expanded(
              flex: 5,
              child: SizedBox(
                height: 42,
                child: OutlinedButton(
                  onPressed: _busy || _expired ? null : _accept,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: go.action,
                    side: BorderSide(
                      color: go.action.withOpacity(0.55),
                      width: 1.3,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    ),
                  ),
                  child: _accepting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: go.action,
                          ),
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            strings.acceptInsteadWithFare(_fare.toStringAsFixed(0)),
                            style: AppTokens.font(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: go.action,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: AppTokens.spaceXs),
            Expanded(
              flex: 3,
              child: SizedBox(
                height: 42,
                child: TextButton(
                  onPressed: _busy ? null : _decline,
                  style: TextButton.styleFrom(
                    foregroundColor: go.muted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      side: BorderSide(color: go.border),
                    ),
                  ),
                  child: Text(
                    strings.skipLabel,
                    style: AppTokens.font(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: go.muted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Circular rider avatar. Uses the rider's photo when the offer payload
/// carries a `rider_photo` URL; otherwise falls back to the first letter of
/// the name (or a generic person icon when there is no name either) so the
/// identity slot never renders empty.
class _RiderAvatar extends StatelessWidget {
  const _RiderAvatar({required this.name, required this.photoUrl, required this.accent});

  final String? name;
  final String? photoUrl;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final initial = (name != null && name!.isNotEmpty)
        ? name!.characters.first.toUpperCase()
        : null;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent.withOpacity(0.4), width: 2),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: photoUrl != null
            ? Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(initial),
                loadingBuilder: (ctx, child, progress) =>
                    progress == null ? child : _fallback(initial),
              )
            : _fallback(initial),
      ),
    );
  }

  Widget _fallback(String? initial) {
    return Container(
      color: accent.withOpacity(0.14),
      alignment: Alignment.center,
      child: initial != null
          ? Text(
              initial,
              style: AppTokens.font(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: accent,
              ),
            )
          : Icon(Icons.person_rounded, color: accent, size: 24),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.tone,
    required this.border,
  });

  final IconData icon;
  final String label;
  final Color tone;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tone),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTokens.font(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}

/// Depleting ring with the remaining seconds at its centre — readable at a
/// glance without having to parse a thin linear bar.
class _CountdownRing extends StatelessWidget {
  const _CountdownRing({
    required this.progress,
    required this.seconds,
    required this.color,
    required this.urgent,
  });

  final double progress;
  final int seconds;
  final Color color;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 3.5,
              backgroundColor: color.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              strokeCap: StrokeCap.round,
            ),
          ),
          Text(
            '$seconds',
            style: AppTokens.money(
              fontSize: urgent ? 19 : 17,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
