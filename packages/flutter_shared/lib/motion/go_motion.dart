import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// Motion primitives for map vehicles.
///
/// **Why this file has no `latlong2` import.** `flutter_shared` deliberately
/// declares every package it imports (see the `url_launcher` note in its
/// pubspec: an import that resolved only because each consuming app happened
/// to depend on the package meant this one did not analyse standalone).
/// `latlong2` is *not* a dependency of `flutter_shared`, and adding it would
/// mean editing `packages/flutter_shared/pubspec.yaml`, which task E11 does
/// not own. So the tween is expressed over [GoLatLng], a two-double value
/// type defined here, and each app converts at the call site — one line in
/// each direction against the `LatLng` it already depends on.
///
/// Everything below is pure: no Flutter widgets, no platform channels, no
/// clock. That is deliberate — it is the part of the interpolation that can
/// be unit-tested without a device (see the note about test ownership in the
/// E11 pull request).

/// An immutable WGS84 coordinate, independent of any mapping package.
@immutable
class GoLatLng {
  const GoLatLng(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GoLatLng && other.lat == lat && other.lng == lng);

  @override
  int get hashCode => Object.hash(lat, lng);

  @override
  String toString() => 'GoLatLng($lat, $lng)';
}

/// Linear interpolation between two coordinates.
///
/// Latitude interpolates plainly. Longitude takes the **shorter way round**,
/// so a pair straddling the antimeridian does not sweep the long way across
/// the globe. Egypt never crosses it, but the correct version costs three
/// lines and removes a class of bug nobody would think to look for.
GoLatLng goLerpLatLng(GoLatLng a, GoLatLng b, double t) {
  final lat = a.lat + (b.lat - a.lat) * t;

  var deltaLng = b.lng - a.lng;
  if (deltaLng > 180) {
    deltaLng -= 360;
  } else if (deltaLng < -180) {
    deltaLng += 360;
  }

  var lng = a.lng + deltaLng * t;
  if (lng > 180) {
    lng -= 360;
  } else if (lng < -180) {
    lng += 360;
  }

  return GoLatLng(lat, lng);
}

/// A [Tween] over map coordinates, used to walk a vehicle marker from the
/// previous fix to the newest one instead of teleporting it.
///
/// Named `LatLngTween` in the plan; it operates on [GoLatLng] for the
/// dependency reason described at the top of this file.
class LatLngTween extends Tween<GoLatLng> {
  LatLngTween({required GoLatLng super.begin, required GoLatLng super.end});

  @override
  GoLatLng lerp(double t) => goLerpLatLng(begin!, end!, t);
}

/// Shortest-path interpolation between two compass bearings in degrees.
///
/// A car turning from 350° to 10° is turning 20° clockwise through north, not
/// 340° anticlockwise. Interpolating the raw numbers spins the marker almost
/// all the way round, which is worse than not animating it at all.
double goLerpHeading(double from, double to, double t) {
  final a = from % 360;
  final b = to % 360;
  var delta = (b - a) % 360;
  if (delta > 180) delta -= 360;
  if (delta < -180) delta += 360;
  final result = (a + delta * t) % 360;
  return result < 0 ? result + 360 : result;
}

/// Timing rules for vehicle motion.
///
/// The publish cadence and the animation duration are the same number seen
/// from two ends of the wire. Lengthening the publish interval to respect the
/// server's rate limit — which E11 does — makes the marker look *worse* unless
/// the receiving side spends that same interval walking the car across the
/// gap. T13 and T28 both recorded this independently, which is why the two
/// changes are required to ship together.
abstract final class GoMotion {
  /// Never animate faster than this; below it the tween is imperceptible and
  /// only costs frames.
  static const Duration minFixTween = Duration(milliseconds: 250);

  /// Never animate slower than this. A gap longer than this means fixes have
  /// stopped arriving (tunnel, lost signal, app killed) — dragging the car
  /// smoothly across ten seconds of missing data invents a journey that did
  /// not happen. Hold position instead and let the marker go stale honestly.
  static const Duration maxFixTween = Duration(seconds: 6);

  /// Used for the first fix of a session, when no interval has been measured.
  static const Duration defaultFixTween = Duration(milliseconds: 1500);

  /// Clamp a measured inter-fix interval into a usable animation duration.
  ///
  /// Pass the wall-clock gap between the previous fix and this one. The tween
  /// then finishes just as the next fix is expected, so the car arrives rather
  /// than stopping short and jerking forward — and, critically, it never runs
  /// *past* the newest known position. This function is the only place that
  /// decides motion timing.
  static Duration resolveFixTween(Duration? measured) {
    if (measured == null) return defaultFixTween;
    if (measured <= Duration.zero) return minFixTween;
    if (measured < minFixTween) return minFixTween;
    if (measured > maxFixTween) return maxFixTween;
    return measured;
  }

  /// True when a gap between fixes is long enough that interpolating across
  /// it would be fabricating movement rather than smoothing it.
  static bool isStaleGap(Duration measured) => measured > maxFixTween;

  /// Metres between two coordinates (spherical earth). Used to decide whether
  /// a new fix is real movement or GPS jitter around a parked car.
  static double metresBetween(GoLatLng a, GoLatLng b) {
    const earthRadiusM = 6371000.0;
    final dLat = _radians(b.lat - a.lat);
    final dLng = _radians(b.lng - a.lng);
    final lat1 = _radians(a.lat);
    final lat2 = _radians(b.lat);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
  }

  /// Below this, a "new" fix is treated as the car standing still. Consumer
  /// GPS wanders by a few metres when stationary; animating that wander makes
  /// a parked car look like it is drifting down the road.
  static const double jitterThresholdMetres = 1.5;

  static double _radians(double degrees) => degrees * math.pi / 180;
}
