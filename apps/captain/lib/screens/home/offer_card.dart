import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';

/// An incoming ride offer.
///
/// This is the single highest-stakes card in the product: the captain decides
/// on it in a couple of seconds, often at a traffic light. The redesign makes
/// the decision inputs unmissable in priority order —
///
///   1. **the fare**, as an oversized numeral, because that is the decision;
///   2. **how far away the pickup is**, because that is the cost of taking it;
///   3. the route itself;
///   4. the actions.
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
          content: Text(
            'تم إرسال عرضك بمبلغ ${amount.toStringAsFixed(0)} ج.م — بانتظار رد العميل',
          ),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = isDark ? AppTokens.darkSurface : Colors.white;
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final muted = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final border = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;

    return AnimatedBuilder(
      animation: _countdown,
      builder: (context, _) {
        final urgent =
            widget.showCountdown && _secondsLeft <= 5 && !_expired;
        final accent = urgent ? AppTokens.danger : AppTokens.primary;

        return Opacity(
          opacity: _expired ? 0.5 : 1,
          child: Container(
            margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              border: Border.all(
                color: urgent ? AppTokens.danger.withOpacity(0.5) : border,
                width: urgent ? 1.5 : 1,
              ),
              boxShadow: AppTokens.shadowOffer,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(accent, text, muted, urgent),
                _buildMetaStrip(muted, border),
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  child: Column(
                    children: [
                      _buildRoute(text, muted, border),
                      const SizedBox(height: AppTokens.spaceMd),
                      _buildActions(muted, border),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Fare and countdown, side by side. The fare gets the whole remaining
  /// width and can shrink to fit rather than overflow.
  Widget _buildHeader(Color accent, Color text, Color muted, bool urgent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceMd,
        AppTokens.spaceMd,
        AppTokens.spaceMd,
        AppTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            AppTokens.primary.withOpacity(0.10),
            AppTokens.primary.withOpacity(0.02),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _expired
                      ? 'انتهت مهلة العرض'
                      : (_fareIsRiderOffer
                          ? 'سعر العميل المقترح'
                          : 'السعر التقديري'),
                  style: AppTokens.font(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _expired ? AppTokens.danger : muted,
                  ),
                ),
                const SizedBox(height: 2),
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
                          fontSize: 38,
                          color: AppTokens.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'ج.م',
                        style: AppTokens.font(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.primary,
                        ),
                      ),
                    ],
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
  Widget _buildMetaStrip(Color muted, Color border) {
    final chips = <Widget>[
      if (_pickupKm != null)
        _MetaChip(
          icon: Icons.near_me_rounded,
          label: 'الوصول ${_pickupKm!.toStringAsFixed(1)} كم',
          tone: AppTokens.accent,
          border: border,
        ),
      if (_tripKm != null)
        _MetaChip(
          icon: Icons.straighten_rounded,
          label: 'الرحلة ${_tripKm!.toStringAsFixed(1)} كم',
          tone: muted,
          border: border,
        ),
      if (_durationMin != null)
        _MetaChip(
          icon: Icons.schedule_rounded,
          label: '~$_durationMin دقيقة',
          tone: muted,
          border: border,
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

  Widget _buildRoute(Color text, Color muted, Color border) {
    final pickup = widget.offer['pickup_address']?.toString().trim();
    final dropoff = widget.offer['dropoff_address']?.toString().trim();

    return Column(
      children: [
        _addressRow(
          dotColor: AppTokens.primary,
          label: 'من',
          value: (pickup == null || pickup.isEmpty) ? 'نقطة الالتقاط' : pickup,
          text: text,
          muted: muted,
        ),
        // Connector, inset to sit under the dot in both text directions.
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 5),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              width: 2,
              height: 16,
              color: border,
            ),
          ),
        ),
        _addressRow(
          dotColor: AppTokens.danger,
          label: 'إلى',
          value: (dropoff == null || dropoff.isEmpty) ? 'الوجهة' : dropoff,
          text: text,
          muted: muted,
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
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor.withOpacity(0.2),
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
                style: AppTokens.font(fontSize: 11, color: muted),
              ),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTokens.font(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: text,
                  height: 1.35,
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
  Widget _buildActions(Color muted, Color border) {
    final disabled = _busy || _expired;

    if (_bidSent != null) return _buildBidSentState(muted, border);

    return Column(
      children: [
        SizedBox(
          height: AppTokens.primaryActionHeight,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: disabled ? null : _accept,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTokens.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTokens.primary.withOpacity(0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              ),
            ),
            child: _accepting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 21),
                        const SizedBox(width: AppTokens.spaceXs),
                        Text(
                          'قبول بـ ${_fare.toStringAsFixed(0)} ج.م',
                          style: AppTokens.font(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
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
                height: AppTokens.tapTarget,
                child: OutlinedButton(
                  onPressed: disabled ? null : _counterOffer,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTokens.primary,
                    side: BorderSide(
                      color: disabled
                          ? border
                          : AppTokens.primary.withOpacity(0.55),
                      width: 1.4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    ),
                  ),
                  child: _bidding
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: AppTokens.primary,
                          ),
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.price_change_rounded, size: 19),
                              const SizedBox(width: 6),
                              Text(
                                'سعر معدّل',
                                style: AppTokens.font(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTokens.primary,
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
                height: AppTokens.tapTarget,
                child: TextButton(
                  onPressed: disabled ? null : _decline,
                  style: TextButton.styleFrom(
                    foregroundColor: muted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      side: BorderSide(color: border),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close_rounded, size: 18, color: muted),
                        const SizedBox(width: 5),
                        Text(
                          'تخطي',
                          style: AppTokens.font(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: muted,
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
  Widget _buildBidSentState(Color muted, Color border) {
    final amount = _bidSent!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceSm,
            vertical: AppTokens.spaceSm,
          ),
          decoration: BoxDecoration(
            color: AppTokens.success.withOpacity(0.10),
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            border: Border.all(color: AppTokens.success.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.hourglass_top_rounded,
                size: 19,
                color: AppTokens.success,
              ),
              const SizedBox(width: AppTokens.spaceXs),
              Expanded(
                child: Text(
                  'أرسلت عرضًا بمبلغ ${amount.toStringAsFixed(0)} ج.م — بانتظار رد العميل',
                  style: AppTokens.font(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.success,
                    height: 1.35,
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
                height: AppTokens.tapTarget,
                child: OutlinedButton(
                  onPressed: _busy || _expired ? null : _accept,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTokens.primary,
                    side: BorderSide(
                      color: AppTokens.primary.withOpacity(0.55),
                      width: 1.4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    ),
                  ),
                  child: _accepting
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: AppTokens.primary,
                          ),
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'قبول بـ ${_fare.toStringAsFixed(0)} ج.م بدلاً منه',
                            style: AppTokens.font(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppTokens.primary,
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
                height: AppTokens.tapTarget,
                child: TextButton(
                  onPressed: _busy ? null : _decline,
                  style: TextButton.styleFrom(
                    foregroundColor: muted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      side: BorderSide(color: border),
                    ),
                  ),
                  child: Text(
                    'تخطي',
                    style: AppTokens.font(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: muted,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTokens.font(
              fontSize: 12,
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
      width: 54,
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 4,
              backgroundColor: color.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
              strokeCap: StrokeCap.round,
            ),
          ),
          Text(
            '$seconds',
            style: AppTokens.money(
              fontSize: urgent ? 21 : 19,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
