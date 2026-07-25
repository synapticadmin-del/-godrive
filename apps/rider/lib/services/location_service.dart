import 'dart:async';

import 'package:latlong2/latlong.dart';

import 'app_state.dart';

/// A driving route between two points, as returned by the backend.
///
/// The backend (`apps/api/src/lib/routing.ts`) asks OSRM for a real driving
/// route and returns its full `geometry` — the ordered list of coordinates the
/// car will actually follow through the street network. If OSRM is
/// unreachable it falls back to a straight line with a 1.35× distance
/// correction, and reports that via [isApproximate].
///
/// Before this class existed the Rider app threw the geometry away and drew a
/// two-point straight line, so the on-screen path cut across buildings and the
/// Nile instead of following roads. That was the bug riders were seeing.
class RoutePreview {
  const RoutePreview({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
    required this.isApproximate,
    this.fareTotal,
    this.currency,
  });

  /// The polyline the driver will follow. Always contains at least the
  /// origin and destination.
  final List<LatLng> points;

  /// Driving distance in kilometres (not straight-line distance).
  final double distanceKm;

  /// Estimated driving time in minutes.
  final int durationMin;

  /// True when the backend fell back to a straight-line estimate because the
  /// routing engine was unavailable. The UI should soften its wording
  /// ("تقريبي") rather than presenting it as an exact route.
  final bool isApproximate;

  /// Estimated fare total, when the endpoint returned pricing.
  final double? fareTotal;

  /// ISO currency code for [fareTotal].
  final String? currency;

  bool get hasRealGeometry => points.length > 2;

  /// Human-readable duration, e.g. "١٦ دقيقة" / "1 س 5 د".
  String durationLabel({required bool isArabic}) {
    if (durationMin < 60) {
      return isArabic ? '$durationMin دقيقة' : '$durationMin min';
    }
    final h = durationMin ~/ 60;
    final m = durationMin % 60;
    if (isArabic) {
      return m == 0 ? '$h ساعة' : '$h س $m د';
    }
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  /// Human-readable distance, e.g. "٣.٤ كم" / "800 m".
  String distanceLabel({required bool isArabic}) {
    if (distanceKm < 1) {
      final m = (distanceKm * 1000).round();
      return isArabic ? '$m متر' : '$m m';
    }
    final v = distanceKm.toStringAsFixed(1);
    return isArabic ? '$v كم' : '$v km';
  }

  /// Parses the payload returned by `POST /trips/estimate`.
  ///
  /// The endpoint responds with `{ distanceKm, durationMin, geometry, source,
  /// fare: { total, currency, ... } }` where `geometry` is `[[lat, lng], ...]`.
  /// Every field is parsed defensively — a malformed geometry must never crash
  /// the booking flow, it should just degrade to a straight line.
  static RoutePreview fromEstimate(
    Map<String, dynamic> json, {
    required LatLng origin,
    required LatLng destination,
  }) {
    final points = _parseGeometry(json['geometry']);

    final fare = json['fare'];
    double? total;
    String? currency;
    if (fare is Map) {
      total = _toDouble(fare['total']);
      final c = fare['currency'];
      if (c is String && c.isNotEmpty) currency = c;
    }

    final source = json['source'];
    // `haversine` means OSRM was unreachable and the backend approximated.
    final approximate = source is String && source != 'osrm';

    return RoutePreview(
      points: points.length >= 2 ? points : [origin, destination],
      distanceKm: _toDouble(json['distanceKm']) ?? 0,
      durationMin: _toInt(json['durationMin']) ?? 0,
      isApproximate: approximate || points.length < 2,
      fareTotal: total,
      currency: currency,
    );
  }

  /// Geometry is `[[lat, lng], ...]`. Guards against nulls, strings and
  /// out-of-range values so a bad payload can't put a marker in the ocean.
  static List<LatLng> _parseGeometry(dynamic raw) {
    if (raw is! List) return const [];
    final out = <LatLng>[];
    for (final entry in raw) {
      if (entry is! List || entry.length < 2) continue;
      final lat = _toDouble(entry[0]);
      final lng = _toDouble(entry[1]);
      if (lat == null || lng == null) continue;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;
      out.add(LatLng(lat, lng));
    }
    return out;
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _toInt(dynamic v) {
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

/// A place returned from search or reverse geocoding.
class PlaceResult {
  const PlaceResult({
    required this.label,
    required this.location,
    this.secondary,
    this.distanceKm,
  });

  /// Primary display name, e.g. "مسجد الاباصيري".
  final String label;

  /// Coordinates of the place.
  final LatLng location;

  /// Supporting line, e.g. the governorate or full address.
  final String? secondary;

  /// Straight-line distance from the rider, used for sorting and display.
  final double? distanceKm;

  PlaceResult copyWith({double? distanceKm}) => PlaceResult(
        label: label,
        location: location,
        secondary: secondary,
        distanceKm: distanceKm ?? this.distanceKm,
      );

  String? distanceLabel({required bool isArabic}) {
    final d = distanceKm;
    if (d == null) return null;
    if (d < 1) {
      final m = (d * 1000).round();
      return isArabic ? '$m م' : '$m m';
    }
    return isArabic ? '${d.toStringAsFixed(1)} كم' : '${d.toStringAsFixed(1)} km';
  }
}

/// Geocoding and routing, routed through the GoDrive backend.
///
/// Why the backend and not Nominatim directly:
///  * Nominatim's usage policy forbids calling it straight from end-user apps.
///    Doing so risks the whole app's IP range being blocked.
///  * The backend already caches reverse-geocode results in KV for 30 days and
///    rate-limits the endpoints, so repeated lookups are fast and cheap.
///  * Keeping the provider server-side means switching providers later needs
///    no app release.
class LocationService {
  LocationService(this._state);

  final AppState _state;

  static const _distance = Distance();

  /// Fetches the real driving route between two points.
  ///
  /// Returns `null` only if the request fails outright; callers should then
  /// fall back to showing a straight line rather than blocking the booking.
  Future<RoutePreview?> fetchRoute({
    required LatLng origin,
    required LatLng destination,
    String city = 'cairo',
  }) async {
    try {
      final res = await _state.estimateTrip(
        pickupLat: origin.latitude,
        pickupLng: origin.longitude,
        dropoffLat: destination.latitude,
        dropoffLng: destination.longitude,
      );
      return RoutePreview.fromEstimate(
        res,
        origin: origin,
        destination: destination,
      );
    } catch (_) {
      return null;
    }
  }

  /// Searches for places by name, biased toward the rider's current position.
  ///
  /// Results are sorted by proximity so "مسجد" returns the nearby mosque
  /// first rather than one in another governorate — the behaviour riders
  /// expect from Uber/Careem/inDrive.
  Future<List<PlaceResult>> searchPlaces(
    String query, {
    LatLng? near,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const [];

    final res = await _state.apiGet('/geocode/search?q=${Uri.encodeComponent(q)}');
    final raw = res['results'];
    if (raw is! List) return const [];

    final places = <PlaceResult>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final lat = RoutePreview._toDouble(item['lat']);
      final lng = RoutePreview._toDouble(item['lng']);
      if (lat == null || lng == null) continue;

      final label = (item['label'] ?? item['display_name'] ?? '').toString();
      if (label.isEmpty) continue;

      final location = LatLng(lat, lng);
      final parts = label.split(',');

      places.add(PlaceResult(
        label: parts.first.trim(),
        secondary: parts.length > 1 ? parts.skip(1).join(',').trim() : null,
        location: location,
        distanceKm: near == null
            ? null
            : _distance.as(LengthUnit.Kilometer, near, location).toDouble(),
      ));
    }

    if (near != null) {
      places.sort((a, b) => (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0));
    }
    return places;
  }

  /// Turns coordinates into a street address.
  ///
  /// Used by the centre-pin flow so the rider sees "شارع 9، المعادي" instead
  /// of "29.9592, 31.2612" while dragging the map.
  Future<String?> reverseGeocode(LatLng point) async {
    try {
      final res = await _state.apiGet(
        '/geocode/reverse?lat=${point.latitude}&lng=${point.longitude}',
      );
      final address = res['address'] ?? res['display_name'];
      if (address is String && address.trim().isNotEmpty) return address.trim();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Formats coordinates as a last-resort label when geocoding fails.
  static String coordinateLabel(LatLng p) =>
      '${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)}';
}

/// Debounces rapid keystrokes so we issue one request per pause in typing
/// rather than one per character — important because the backend rate-limits
/// search to 15 requests/minute.
class Debouncer {
  Debouncer({this.milliseconds = 350});

  final int milliseconds;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }

  void cancel() => _timer?.cancel();
  void dispose() => _timer?.cancel();
}
