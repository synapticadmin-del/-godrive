import 'package:flutter/widgets.dart';

import '../motion/go_motion.dart';
import 'vehicle_map_marker.dart';

/// A [VehicleMapMarker] that *walks* between GPS fixes instead of teleporting.
///
/// ## Why this exists
///
/// The captain app used to publish a location on every 10 m of movement, which
/// at driving speed is 1.7–3.9× the server's own rate limit — so the surplus
/// was 429'd and thrown away. The rider watched the car move, freeze for 38–47
/// seconds, then jump. E11 fixes the publish side by pacing it inside the
/// server's budget, and that fix on its own makes the marker look **worse**:
/// fewer, further-apart fixes mean bigger jumps. Interpolation is the other
/// half, and the two must ship in the same release (T13 and T28 both say so).
///
/// ## What it will not do
///
/// It never extrapolates. The tween runs from the previous fix to the newest
/// one and stops. If the next fix does not arrive, the car holds its last
/// **known** position rather than continuing along its last heading — a
/// marker that keeps driving on invented data is worse than one that visibly
/// stops, because a rider reads it as truth.
///
/// Two cases skip the animation deliberately:
///  * movement below [GoMotion.jitterThresholdMetres] — stationary GPS wander,
///    animating it makes a parked car drift down the street;
///  * gaps longer than [GoMotion.maxFixTween] — the signal was lost, and
///    sliding smoothly across the missing minute would fabricate a journey.
///
/// ## Using it with a map
///
/// `flutter_shared` does not depend on `flutter_map` or `latlong2`, so this
/// widget cannot build a `Marker` for you. Pass [builder] and place the
/// interpolated coordinate yourself:
///
/// ```dart
/// AnimatedVehicleMarker(
///   position: GoLatLng(fix.latitude, fix.longitude),
///   heading: fix.heading,
///   builder: (context, p, heading) => FlutterMap(
///     children: [
///       MarkerLayer(markers: [
///         Marker(
///           point: LatLng(p.lat, p.lng),
///           child: VehicleMapMarker(heading: heading),
///         ),
///       ]),
///     ],
///   ),
/// )
/// ```
///
/// With no [builder] it simply draws the car, interpolating the heading only —
/// useful where the marker's screen position is handled elsewhere.
class AnimatedVehicleMarker extends StatefulWidget {
  const AnimatedVehicleMarker({
    super.key,
    required this.position,
    this.heading,
    this.fixInterval,
    this.color,
    this.size = 54,
    this.showShadow = true,
    this.builder,
  });

  /// The newest known position. Changing this starts a tween from wherever
  /// the marker currently is.
  final GoLatLng position;

  /// Bearing in degrees clockwise from north, or null to leave the car
  /// pointing up. Interpolated the short way round.
  final double? heading;

  /// The measured gap between the previous fix and this one. When null the
  /// widget measures it from its own clock, which is what a live stream
  /// wants; pass a value explicitly when replaying recorded fixes.
  final Duration? fixInterval;

  /// Car body colour, forwarded to [VehicleMapMarker].
  final Color? color;

  /// Logical size of the car, forwarded to [VehicleMapMarker].
  final double size;

  /// Ground shadow, forwarded to [VehicleMapMarker].
  final bool showShadow;

  /// Receives the interpolated coordinate and heading on every frame of the
  /// tween. Return whatever places it on your map.
  final Widget Function(BuildContext context, GoLatLng position, double? heading)?
      builder;

  @override
  State<AnimatedVehicleMarker> createState() => _AnimatedVehicleMarkerState();
}

class _AnimatedVehicleMarkerState extends State<AnimatedVehicleMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Where the tween starts — the marker's position when the newest fix
  /// landed, which is not necessarily the previous fix: retargeting mid-flight
  /// must start from where the car visibly *is*, or it snaps backwards.
  late GoLatLng _from;
  late GoLatLng _to;

  double? _headingFrom;
  double? _headingTo;

  /// Wall clock of the last accepted fix, for measuring the interval.
  DateTime? _lastFixAt;

  @override
  void initState() {
    super.initState();
    _from = widget.position;
    _to = widget.position;
    _headingFrom = widget.heading;
    _headingTo = widget.heading;
    _controller = AnimationController(
      vsync: this,
      duration: GoMotion.defaultFixTween,
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedVehicleMarker oldWidget) {
    super.didUpdateWidget(oldWidget);

    final positionChanged = widget.position != oldWidget.position;
    final headingChanged = widget.heading != oldWidget.heading;

    if (!positionChanged && !headingChanged) return;

    final now = DateTime.now();
    final measured = widget.fixInterval ??
        (_lastFixAt == null ? null : now.difference(_lastFixAt!));
    if (positionChanged) _lastFixAt = now;

    final current = _currentPosition();
    final metres = GoMotion.metresBetween(current, widget.position);

    // Snap, do not animate: stationary jitter, or a gap so long that
    // interpolating it would invent movement that never happened.
    final staleGap = measured != null && GoMotion.isStaleGap(measured);
    if (metres < GoMotion.jitterThresholdMetres || staleGap) {
      setState(() {
        _from = widget.position;
        _to = widget.position;
        _headingFrom = widget.heading;
        _headingTo = widget.heading;
      });
      _controller.value = 1;
      return;
    }

    setState(() {
      _from = current;
      _to = widget.position;
      _headingFrom = _currentHeading();
      _headingTo = widget.heading;
    });

    _controller
      ..duration = GoMotion.resolveFixTween(measured)
      ..forward(from: 0);
  }

  GoLatLng _currentPosition() =>
      goLerpLatLng(_from, _to, _controller.value);

  double? _currentHeading() {
    final from = _headingFrom;
    final to = _headingTo;
    if (to == null) return from;
    if (from == null) return to;
    return goLerpHeading(from, to, _controller.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final position = _currentPosition();
        final heading = _currentHeading();

        final builder = widget.builder;
        if (builder != null) return builder(context, position, heading);

        return VehicleMapMarker(
          heading: heading,
          color: widget.color,
          size: widget.size,
          showShadow: widget.showShadow,
        );
      },
    );
  }
}
