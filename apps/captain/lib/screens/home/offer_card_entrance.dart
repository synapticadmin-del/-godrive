import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';

/// Entrance choreography for a list of offer cards.
///
/// Cards fly in from the side and settle into place, and the list builds from
/// the top down — the first card lands first, each following card a beat
/// later. That ordering is the point: it walks the captain's eye to the top
/// of the list, which is where the newest, most relevant work sits, instead
/// of having a screenful of cards appear at once and forcing a scan.
///
/// Direction follows text direction, so in the Arabic RTL layout the cards
/// enter from the right — the side the reading eye already starts from — and
/// from the left in LTR. Hardcoding a side would have made the motion fight
/// the layout in one of the two locales.
///
/// The travel eases out with a slight overshoot damped by [Curves.easeOutCubic]
/// so a card *arrives* rather than stopping dead, which is what makes the
/// settle read as physical.
class OfferCardEntrance extends StatelessWidget {
  const OfferCardEntrance({
    super.key,
    required this.index,
    required this.child,
    this.stagger = const Duration(milliseconds: 70),
    this.duration = const Duration(milliseconds: 460),
  });

  /// Position in the list. Drives the delay, so index 0 settles first.
  final int index;

  final Widget child;

  /// Gap between one card starting and the next.
  final Duration stagger;

  /// Travel time for a single card.
  final Duration duration;

  /// Past this many cards the delay stops growing. Without a cap, a long list
  /// would leave the last card waiting seconds before it appeared — and on a
  /// refresh the captain would watch an empty screen fill in slow motion.
  static const int _maxStaggerSteps = 8;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final steps = index < _maxStaggerSteps ? index : _maxStaggerSteps;
    final delay = stagger * steps;

    // Positive x is toward the end of the reading direction in Flutter's
    // slide transform, so RTL enters from +x (screen right).
    final from = rtl ? 0.35 : -0.35;

    return child
        .animate()
        .fadeIn(delay: delay, duration: duration, curve: Curves.easeOut)
        .slideX(
          begin: from,
          end: 0,
          delay: delay,
          duration: duration,
          curve: Curves.easeOutCubic,
        )
        // A touch of scale on arrival: the card reads as coming toward the
        // captain and coming to rest, not just sliding across a plane.
        .scaleXY(
          begin: 0.94,
          end: 1,
          delay: delay,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
  }
}

/// Shared list padding so the map sheet and the Available Trips tab space
/// their cards identically.
const EdgeInsets kOfferListPadding = EdgeInsets.fromLTRB(
  AppTokens.spaceMd,
  AppTokens.spaceSm,
  AppTokens.spaceMd,
  AppTokens.space2xl,
);
