import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

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
class OfferCard extends StatefulWidget {
  const OfferCard({super.key, required this.offer});

  final Map<String, dynamic> offer;

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
  bool _expired = false;
  int _lastWholeSecond = _window;

  int get _secondsLeft => (_window * (1 - _countdown.value)).ceil();

  @override
  void initState() {
    super.initState();
    _countdown.forward();
    _countdown.addStatusListener(_onCountdownStatus);

    // Haptic ticks in the final five seconds, driven off wall-clock rather
    // than a rebuild, so the pulse stays steady regardless of frame timing.
    //
    // Suppressed while offline: the card is not rendered in that state, and a
    // phone buzzing in a captain's pocket for an offer they cannot see is
    // worse than silence.
    _hapticTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = _secondsLeft;
      if (left != _lastWholeSecond) {
        _lastWholeSecond = left;
        final online = context.read<CaptainState>().online;
        if (online && left > 0 && left <= 5) HapticFeedback.lightImpact();
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

  Future<void> _accept() async {
    if (_accepting || _expired) return;

    final state = context.read<CaptainState>();
    // Closes the gap between the tap landing and this frame: the captain can
    // toggle offline while the card is mid-countdown, and `/trips/:id/accept`
    // does not check `is_online`, so the server would happily assign the trip.
    if (!state.online) return;

    setState(() => _accepting = true);
    HapticFeedback.mediumImpact();
    _countdown.stop();

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

  void _decline() {
    if (_accepting) return;
    HapticFeedback.lightImpact();
    final id = widget.offer['id'];
    if (id is String) context.read<CaptainState>().decline(id);
  }

  // ---------------------------------------------------------------
  // Data access
  // ---------------------------------------------------------------

  double get _fare =>
      (widget.offer['estimated_fare'] as num?)?.toDouble() ?? 0;

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
    // Strict online guard. A captain who is offline must not see trip cards
    // at all — not greyed out, not expired, absent.
    //
    // This is load-bearing rather than cosmetic: neither `/captain/offers`
    // nor `/captain/nearby-requests` filters by `is_online` server-side, so
    // the poll keeps returning live trips after the captain goes offline. A
    // card left on screen would then hand them a tappable "accept" for work
    // they are not supposed to be receiving. `select` rebuilds only when the
    // flag actually flips, rather than on every unrelated CaptainState
    // notification (this widget rebuilds ~60fps from its own countdown as it
    // is).
    final online = context.select<CaptainState, bool>((s) => s.online);
    if (!online) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final muted = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final border = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;

    // Frosted glass. The card floats over the map, so a translucent, blurred
    // surface keeps the captain's surroundings faintly legible underneath
    // instead of punching an opaque hole through the view.
    //
    // Opacity is kept high (0.82/0.86) rather than fashionably low: this is
    // the highest-stakes card in the product, read in seconds, often in
    // direct sunlight. Glass must not cost legibility.
    final glassTop = isDark
        ? AppTokens.darkSurface.withOpacity(0.86)
        : Colors.white.withOpacity(0.86);
    final glassBottom = isDark
        ? AppTokens.darkPanel.withOpacity(0.82)
        : Colors.white.withOpacity(0.78);

    return AnimatedBuilder(
      animation: _countdown,
      builder: (context, _) {
        final urgent = _secondsLeft <= 5 && !_expired;
        final accent = urgent ? AppTokens.danger : AppTokens.primary;

        return Opacity(
          opacity: _expired ? 0.5 : 1,
          child: Container(
            margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              boxShadow: AppTokens.shadowOffer,
            ),
            clipBehavior: Clip.antiAlias,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTokens.radiusLg),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [glassTop, glassBottom],
                    ),
                    borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                    border: Border.all(
                      // A brighter rim than a flat border — glass catches
                      // light at its edge, which is what separates it from
                      // the surface behind it.
                      color: urgent
                          ? AppTokens.danger.withOpacity(0.55)
                          : isDark
                              ? Colors.white.withOpacity(0.14)
                              : border.withOpacity(0.9),
                      width: urgent ? 1.5 : 1,
                    ),
                  ),
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
              ),
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
                  _expired ? 'انتهت مهلة العرض' : 'رحلة جديدة',
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
          const SizedBox(width: AppTokens.spaceSm),
          _CountdownRing(
            progress: 1 - _countdown.value,
            seconds: _expired ? 0 : _secondsLeft,
            color: accent,
            urgent: urgent,
          ),
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
          label: '~${_durationMin} دقيقة',
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

  Widget _buildActions(Color muted, Color border) {
    final disabled = _accepting || _expired;

    return Row(
      children: [
        Expanded(
          flex: 5,
          child: SizedBox(
            height: AppTokens.primaryActionHeight,
            child: ElevatedButton(
              onPressed: disabled ? null : _accept,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTokens.primary,
                foregroundColor: Colors.white,
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
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_rounded, size: 21),
                        const SizedBox(width: AppTokens.spaceXs),
                        Text(
                          'قبول الرحلة',
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
        const SizedBox(width: AppTokens.spaceXs),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: AppTokens.primaryActionHeight,
            child: OutlinedButton(
              onPressed: disabled ? null : _decline,
              style: OutlinedButton.styleFrom(
                foregroundColor: muted,
                side: BorderSide(color: border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
              ),
              child: Text(
                'رفض',
                style: AppTokens.font(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
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
