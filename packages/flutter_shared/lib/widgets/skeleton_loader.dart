import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// How long one sheen takes to cross a placeholder.
const Duration _kSweepDuration = Duration(milliseconds: 1450);

/// A rectangular loading placeholder carrying a slow sheen across itself.
///
/// The movement is load-bearing, not decoration. A static grey block on a slow
/// Egyptian 3G connection reads as a broken layout; a moving one reads as
/// content on its way. The class has always *documented* a shimmer — it just
/// never drew one.
///
/// Colours resolve through [GoTheme], so a placeholder sits on the same ramp as
/// the panel holding it. This widget used to branch on
/// `Theme.of(context).brightness` by hand and pull the legacy `dark*` scale,
/// which has drifted from the `night*` surfaces the rest of the system uses —
/// a skeleton row on a night panel came out faintly blue against neutral
/// charcoal.
///
/// Inside a [SkeletonList] every box shares that list's single animation, so
/// the rows light up as one surface rather than fifteen boxes blinking out of
/// step. Standalone, a box drives its own ticker.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _own = AnimationController(
    vsync: this,
    duration: _kSweepDuration,
  );

  /// The list-wide sweep, when this box sits under a [SkeletonList].
  Animation<double>? _shared;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shared = _SkeletonSweep.maybeOf(context);

    // Stay still when a list already drives the sweep, and when the platform
    // asks for reduced motion — an endlessly repeating shimmer is precisely
    // the ambient movement that setting exists to silence.
    final driven = _shared != null || _reduceMotion(context);
    if (driven) {
      if (_own.isAnimating) _own.stop();
    } else if (!_own.isAnimating) {
      _own.repeat();
    }
  }

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    if (_reduceMotion(context)) return _fill(go, null);

    final sweep = _shared ?? _own;
    return AnimatedBuilder(
      animation: sweep,
      builder: (_, __) => _fill(go, sweep.value),
    );
  }

  /// Paints the placeholder. A null [t] means "no animation" and yields a flat
  /// fill instead of a gradient.
  Widget _fill(GoTheme go, double? t) {
    final base = go.surface;

    // One step up the ramp after dark; a clean white sheen in daylight. The
    // light ramp's `surface` and `elevated` are only a couple of hex points
    // apart (#F1F5F9 against #F3F4F6), so a sweep between those two would be
    // invisible — `panel` gives the highlight somewhere to travel.
    final highlight = go.isDark ? go.elevated : go.panel;

    Gradient? gradient;
    if (t != null) {
      // Follow the reading direction: a sheen running against the text feels
      // like it is undoing the row rather than filling it in.
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final slide = (-1.0 + 2.0 * t) * (rtl ? -1.0 : 1.0);
      gradient = LinearGradient(
        begin: Alignment(slide - 1.0, 0),
        end: Alignment(slide + 1.0, 0),
        colors: [base, highlight, base],
      );
    }

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: gradient == null ? base : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );
  }
}

bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// Carries one list's sweep down to every [SkeletonBox] beneath it.
///
/// Rows built later by the lazy builder join the sweep already in progress
/// instead of starting their own at phase zero.
class _SkeletonSweep extends InheritedWidget {
  const _SkeletonSweep({required this.animation, required super.child});

  final Animation<double> animation;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonSweep>()?.animation;

  @override
  bool updateShouldNotify(_SkeletonSweep oldWidget) =>
      animation != oldWidget.animation;
}

/// Owns the single ticker shared by a [SkeletonList]'s rows.
class _SweepHost extends StatefulWidget {
  const _SweepHost({required this.child});

  final Widget child;

  @override
  State<_SweepHost> createState() => _SweepHostState();
}

class _SweepHostState extends State<_SweepHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kSweepDuration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion(context)) {
      if (_controller.isAnimating) _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _SkeletonSweep(animation: _controller, child: widget.child);
}

/// A full skeleton list with [count] rows, each a leading circle and two text
/// lines — the shape of a typical list or card while it loads.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.count = 5,
    this.itemHeight = 72,
  });

  final int count;

  /// Height of one placeholder row.
  ///
  /// This was declared and then never read, so a caller asking for taller rows
  /// was silently ignored and every row came out the height of its own content.
  /// It now sizes the row.
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return _SweepHost(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        itemBuilder: (_, __) => SizedBox(
          height: itemHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const SkeletonBox(width: 48, height: 48, radius: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      SkeletonBox(width: 160, height: 14),
                      SizedBox(height: 8),
                      SkeletonBox(height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
