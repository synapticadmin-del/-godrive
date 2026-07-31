import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'offers_ws.dart';
import 'trip_ws.dart';

/// Resolves the multipart MIME type for a picked image from its file
/// extension. `http.MultipartFile.fromPath` without an explicit `contentType`
/// sends the part as application/octet-stream, which POST /user/avatar and
/// POST /captain/upload reject with UNSUPPORTED_TYPE even for a valid photo.
MediaType imageMediaTypeForPath(String path) {
  final ext = path.split('.').last.toLowerCase();
  switch (ext) {
    case 'png':
      return MediaType('image', 'png');
    case 'webp':
      return MediaType('image', 'webp');
    case 'heic':
      return MediaType('image', 'heic');
    case 'heif':
      return MediaType('image', 'heif');
    case 'jpg':
    case 'jpeg':
    default:
      return MediaType('image', 'jpeg');
  }
}

class CaptainState extends ChangeNotifier {
  bool loading = true;
  bool online = false;
  String? token;
  Map<String, dynamic>? user;
  Map<String, dynamic>? captain;
  Map<String, dynamic>? activeTrip;

  /// The captain's current approval state ('pending' | 'approved' | 'rejected'),
  /// read from the latest /auth/me payload. MainShell and the onboarding
  /// wizard watch this so an admin decision flips the app from the document
  /// queue to the live map without a cold restart.
  String? get approvalStatus =>
      (captain?['approval_status'] ?? captain?['status'])?.toString();
  bool get isApproved => approvalStatus == 'approved';
  List<Map<String, dynamic>> offers = [];
  String? error;

  // -------------------------------------------------------------------
  // Search radius
  // -------------------------------------------------------------------

  /// How far out the captain wants to be offered work, in km.
  ///
  /// This used to be widget state inside the "رحلات متاحة" screen, so it
  /// filtered that one list and nothing else: the map sheet, the tab badge,
  /// the pushed offers and the FCM notifications all kept arriving for trips
  /// the captain had explicitly excluded. It now lives here — persisted
  /// locally and mirrored onto the captain row (POST /captain/search-radius)
  /// so dispatch honours it too — and every offer surface reads this one
  /// number.
  static const double defaultSearchRadiusKm = 15;

  /// The chip set offered in the UI. Kept beside the value it constrains.
  static const List<double> searchRadiusOptions = [5, 10, 15, 25, 40];

  double searchRadiusKm = defaultSearchRadiusKm;

  static const _kSearchRadiusKey = 'searchRadiusKm';

  /// True while a radius change is on its way to the server. The 30s
  /// /auth/me poll adopts the stored column, which would otherwise stomp the
  /// captain's brand-new choice with the old value mid-flight.
  bool _radiusPushInFlight = false;

  /// Last GPS fix seen on the shared position stream. Distances are measured
  /// from here rather than from `captains.last_lat/lng`, which is only as
  /// fresh as the last successful location push.
  Position? lastPosition;

  StreamSubscription<Position>? _positionStreamSub;

  /// Single shared position stream. Both the server location push and the
  /// map camera subscribe to this one broadcast stream instead of each
  /// opening its own GPS stream — two independent `getPositionStream`
  /// subscriptions used to keep the GPS radio hot twice over. Exposed for
  /// UI consumers (the main shell's map) so there is exactly ONE underlying
  /// platform GPS subscription for the whole app.
  final StreamController<Position> _positionCtrl =
      StreamController<Position>.broadcast();
  Stream<Position> get positionStream => _positionCtrl.stream;

  Timer? offersTimer;
  OffersWebSocketService? offersWs;
  String offersWsStatus = 'idle';

  /// Periodic /auth/me refresh so an admin approval (or rejection) reaches
  /// the app without the captain force-quitting. Runs only while a token is
  /// present; 30s is cheap (a single small JSON row) and the latency is the
  /// difference between "stuck on the waiting screen" and "the map opens".
  Timer? _approvalPollTimer;
  static const Duration _approvalPollInterval = Duration(seconds: 30);

  /// Live room socket for the active trip. Opened as soon as a trip is
  /// assigned so status changes, cancellations and chat events reach the
  /// captain immediately instead of on the next offers poll.
  CaptainTripWebSocketService? _tripWs;
  StreamSubscription<Map<String, dynamic>>? _tripWsSub;

  /// Broadcast stream of every event received on the active trip's room
  /// socket. UI surfaces (e.g. the chat screen) subscribe to this to react
  /// the moment a message or status change arrives.
  final StreamController<Map<String, dynamic>> _tripEventsCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get activeTripWsMessages => _tripEventsCtrl.stream;

  Locale locale = const Locale('ar', 'EG');
  ThemeMode themeMode = ThemeMode.system;
  String? fcmToken;

  /// Auth tokens live in the platform keystore (Android Keystore / iOS
  /// Keychain), not SharedPreferences, so a rooted-device backup or a
  /// prefs dump cannot leak a session.
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static String get defaultBaseUrl => const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://api.synapticstudio.tech',
      );

  String baseUrl = defaultBaseUrl;

  /// In-app navigation target. Set when the captain taps "تنقّل للراكب" or
  /// "تنقّل للوجهة"; the main shell switches to the map tab, follows the
  /// captain at a tight zoom, and re-routes to this point as GPS updates
  /// arrive. Null when no in-app navigation is active.
  Map<String, dynamic>? navigationTarget;

  /// Broadcast stream that tells the main shell to flip to the map tab and
  /// begin follow-me navigation to [navigationTarget].
  final StreamController<void> _navigationStartCtrl =
      StreamController<void>.broadcast();
  Stream<void> get navigationStart => _navigationStartCtrl.stream;

  /// Fires the moment a trip becomes *this captain's* — whether they accepted
  /// the rider's fare outright or the rider accepted their counter-offer.
  ///
  /// The main shell listens and switches to the map, because that is where
  /// the job is actually driven: before this, a captain whose price edit was
  /// accepted stayed on the requests list with no indication they had won the
  /// trip until they happened to look at another tab.
  final StreamController<Map<String, dynamic>> _tripAssignedCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get tripAssigned => _tripAssignedCtrl.stream;

  /// The trip id already announced on [tripAssigned]. Guards against a second
  /// jump to the map when the poll and the socket both report the same trip.
  String? _announcedTripId;

  /// Announce a newly assigned trip exactly once.
  void _announceTripAssigned(Map<String, dynamic> trip) {
    final tripId = trip['id'] as String?;
    if (tripId == null || tripId == _announcedTripId) return;
    _announcedTripId = tripId;
    if (!_tripAssignedCtrl.isClosed) _tripAssignedCtrl.add(trip);
  }

  /// Begin in-app turn-by-turn navigation to [lat],[lng]. [headingToPickup]
  /// distinguishes "navigate to the rider" from "navigate to the destination"
  /// for the banner copy. This replaces the old behaviour of deep-linking out
  /// to Google Maps — the captain now stays inside GoDrive with the route on
  /// the live map.
  void startInAppNavigation(double lat, double lng, bool headingToPickup) {
    navigationTarget = {
      'lat': lat,
      'lng': lng,
      'toPickup': headingToPickup,
    };
    if (!_navigationStartCtrl.isClosed) _navigationStartCtrl.add(null);
    notifyListeners();
  }

  /// Stop in-app navigation (trip ended, captain cancelled, or arrived).
  void stopInAppNavigation() {
    navigationTarget = null;
    notifyListeners();
  }

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    token = await _secureStorage.read(key: 'token');
    final raw = prefs.getString('user');
    if (raw != null) {
      // Corrupt cached JSON must not brick startup — the session is still
      // recoverable from /auth/me below.
      try {
        user = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        await prefs.remove('user');
      }
    }

    // Restore the saved theme before the first post-splash frame. Without this
    // the app fell back to ThemeMode.system on every cold start, briefly
    // flashing the OS theme even for a captain who had explicitly chosen light
    // or dark.
    final savedTheme = prefs.getString(_kThemeModeKey);
    if (savedTheme != null) {
      themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == savedTheme,
        orElse: () => ThemeMode.system,
      );
    }

    // Restore the radius before the first offers fetch, otherwise the captain
    // gets one round of 15km results on every cold start regardless of the
    // 5km they chose yesterday.
    final savedRadius = prefs.getDouble(_kSearchRadiusKey);
    if (savedRadius != null && savedRadius > 0) searchRadiusKm = savedRadius;

    loading = false;
    notifyListeners();

    await FcmService.init(onToken: registerDeviceToken);

    if (token != null) {
      // refreshMe() must not be able to abort startup. Previously a transient
      // network failure here threw out of bootstrap(), so startOffersPolling()
      // never ran and the captain received no offers at all until they force
      // quit and relaunched the app.
      try {
        await refreshMe();
      } catch (_) {}
      startOffersPolling();
    }
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// Auto Token Refresh Interceptor for handling 401 Unauthorized exceptions safely
  Future<http.Response> _executeWithAuthInterceptor(Future<http.Response> Function() reqFn) async {
    final res = await reqFn();
    if (res.statusCode == 401 && token != null) {
      final refreshToken = await _secureStorage.read(key: 'refreshToken');
      if (refreshToken != null) {
        try {
          final refreshRes = await http
              .post(
                Uri.parse('$baseUrl/auth/refresh'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'refreshToken': refreshToken}),
              )
              .timeout(const Duration(seconds: 15));
          if (refreshRes.statusCode < 400) {
            final data = jsonDecode(refreshRes.body);
            token = (data['accessToken'] ?? data['token']) as String?;
            if (token != null) {
              await _secureStorage.write(key: 'token', value: token!);
              return await reqFn(); // Retry request with refreshed token
            }
          }
        } catch (_) {}
      }
      await logout(); // Fail-safe logout if token renewal fails
      throw Exception('Session expired. Please log in again.');
    }
    return res;
  }

  Future<Map<String, dynamic>> _post(String path, [Map<String, dynamic>? body]) async {
    final res = await _executeWithAuthInterceptor(() => http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
          body: jsonEncode(body ?? {}),
        )
        .timeout(const Duration(seconds: 15)));
    final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
    if (res.statusCode >= 400) {
      throw Exception(data is Map && data['error'] != null ? data['error'] : 'HTTP ${res.statusCode}');
    }
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await _executeWithAuthInterceptor(() => http
        .get(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15)));
    final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
    if (res.statusCode >= 400) {
      throw Exception(data is Map && data['error'] != null ? data['error'] : 'HTTP ${res.statusCode}');
    }
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> apiGet(String path) => _get(path);
  Future<Map<String, dynamic>> apiPost(String path, [Map<String, dynamic>? body]) => _post(path, body);
  Future<Map<String, dynamic>> apiDelete(String path) async {
    final res = await _executeWithAuthInterceptor(() => http
        .delete(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15)));
    final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
    if (res.statusCode >= 400) {
      throw Exception(data is Map && data['error'] != null ? data['error'] : 'HTTP ${res.statusCode}');
    }
    return Map<String, dynamic>.from(data as Map);
  }

  Future<String?> requestOtp(String email, {String? name}) async {
    final res = await _post('/auth/request-otp', {
      'email': email,
      'role': 'captain',
      if (name != null) 'name': name,
    });
    return res['devCode'] as String?;
  }

  Future<void> verifyOtp(String email, String code) async {
    final res = await _post('/auth/verify-otp', {'email': email, 'code': code});
    token = (res['accessToken'] ?? res['token']) as String?;
    final refresh = res['refreshToken'] as String?;
    user = Map<String, dynamic>.from(res['user'] as Map);
    captain = res['captain'] == null ? null : Map<String, dynamic>.from(res['captain'] as Map);
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.write(key: 'token', value: token!);
    if (refresh != null) await _secureStorage.write(key: 'refreshToken', value: refresh);
    await prefs.setString('user', jsonEncode(user));
    notifyListeners();
    startOffersPolling();
  }

  Future<void> loginWithEmail({required String email, required String password}) async {
    final res = await _post('/auth/login', {'email': email, 'password': password});
    token = (res['accessToken'] ?? res['token']) as String?;
    final refresh = res['refreshToken'] as String?;
    user = Map<String, dynamic>.from(res['user'] as Map);
    captain = res['captain'] == null ? null : Map<String, dynamic>.from(res['captain'] as Map);
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.write(key: 'token', value: token!);
    if (refresh != null) await _secureStorage.write(key: 'refreshToken', value: refresh);
    await prefs.setString('user', jsonEncode(user));
    notifyListeners();
    startOffersPolling();
  }

  Future<void> registerWithEmail({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    final res = await _post('/auth/register', {
      'email': email,
      'password': password,
      'name': name,
      'phone': phone,
      'role': 'captain',
    });
    token = (res['accessToken'] ?? res['token']) as String?;
    user = Map<String, dynamic>.from(res['user'] as Map);
    captain = {'approval_status': 'pending'};
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.write(key: 'token', value: token!);
    await prefs.setString('user', jsonEncode(user));
    notifyListeners();
    startOffersPolling();
  }

  Future<void> refreshMe() async {
    final res = await _get('/auth/me');
    user = Map<String, dynamic>.from(res['user'] as Map);
    captain = res['captain'] == null ? null : Map<String, dynamic>.from(res['captain'] as Map);

    // The stored column is the value dispatch actually filters on, so adopt
    // it — unless the captain has just changed it and the write is still in
    // flight, in which case the local choice is the newer truth.
    final serverRadius = (captain?['search_radius_km'] as num?)?.toDouble();
    if (!_radiusPushInFlight && serverRadius != null && serverRadius > 0) {
      searchRadiusKm = serverRadius;
    }
    // captains.is_online is an INTEGER 0/1 in D1, but tolerate a bool in case
    // the column is ever serialised differently.
    final isOnline = captain?['is_online'];
    online = isOnline == 1 || isOnline == true;

    // Resume location reporting when the server still has this captain marked
    // online (e.g. the app was killed and relaunched). Without this the
    // captain appears online to dispatch while broadcasting no position, so
    // they sit at their last known point and stop receiving nearby offers.
    if (online) {
      _startLocationStream();
    } else {
      _stopLocationStream();
    }
    notifyListeners();
  }

  Future<void> saveProfile({
    required String name,
    required String vehicleMake,
    required String vehicleModel,
    required String vehiclePlate,
  }) async {
    final res = await _post('/captain/profile', {
      'name': name,
      'vehicleMake': vehicleMake,
      'vehicleModel': vehicleModel,
      'vehiclePlate': vehiclePlate,
    });
    captain = Map<String, dynamic>.from(res['captain'] as Map);
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // Profile photo
  // -------------------------------------------------------------------
  //
  // Backed by the same POST/GET/DELETE /user/avatar endpoints the rider app
  // uses (apps/api/src/routes/user.ts) — the column and the route live on
  // `users`, not `captains`, so any authenticated role can use them. Unlike
  // the rider app's AppState, `user` here is always repopulated verbatim
  // from the server on every verifyOtp/login/register/refreshMe call (see
  // above), so `avatar_url` is already the live snake_case column with no
  // separate camelCase key to keep in sync — one less place for the photo to
  // silently fall out of the cached state.

  ImageProvider? get avatarImage {
    final raw = user?['avatar_url'];
    if (raw is! String || raw.isEmpty) return null;
    if (raw.startsWith('http')) return NetworkImage(raw);
    return NetworkImage(
      '$baseUrl$raw',
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    );
  }

  Future<void> uploadAvatar(String filePath) async {
    final res = await _executeWithAuthInterceptor(() async {
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/user/avatar'))
        ..headers.addAll({if (token != null) 'Authorization': 'Bearer $token'})
        ..files.add(await http.MultipartFile.fromPath(
          'file',
          filePath,
          contentType: imageMediaTypeForPath(filePath),
        ));
      final streamed = await req.send().timeout(const Duration(seconds: 45));
      return http.Response.fromStream(streamed);
    });

    final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
    if (res.statusCode >= 400) {
      throw Exception(
        data is Map && data['error'] != null ? data['error'] : 'HTTP ${res.statusCode}',
      );
    }

    // The upload response itself is camelCase (`avatarUrl`), but everything
    // else in this class reads the user row's own `avatar_url` column, so the
    // locally patched copy is stored under that same key for consistency.
    final url = data is Map ? data['avatarUrl'] : null;
    user = {...?user, 'avatar_url': url is String && url.isNotEmpty ? url : null};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(user));
    notifyListeners();
  }

  Future<void> removeAvatar() async {
    await apiDelete('/user/avatar');
    user = {...?user, 'avatar_url': null};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(user));
    notifyListeners();
  }

  Future<Position> _position() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    // Two-phase acquisition. An unbounded getCurrentPosition() blocks for
    // 10-30s on a cold start while the GPS chip resolves a fresh fix, and
    // indoors it can hang indefinitely — which previously froze the "go
    // online" flow and every location push behind that wait. Take the cached
    // fix as an instant fallback, then request a fresh high-accuracy fix that
    // fails fast on a timeout instead of hanging.
    //
    // geolocator 12's Geolocator.getCurrentPosition takes desiredAccuracy and
    // timeLimit as direct named params (a LocationSettings object is the 13+
    // signature and will not compile here); getLastKnownPosition takes none.
    final cached = await Geolocator.getLastKnownPosition();
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (_) {
      // Timed out or errored — a slightly stale fix beats blocking the captain
      // or failing the online toggle outright.
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Check GPS service is enabled before going online. Returns false (and
  /// sets [gpsError]) if location services are disabled — the UI should
  /// show a dialog prompting the captain to enable GPS.
  String? gpsError;

  Future<bool> checkGpsReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      gpsError = 'خدمة الموقع (GPS) معطّلة. فعّلها للعمل.';
      notifyListeners();
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        gpsError = 'يجب منح إذن الوصول للموقع.';
        notifyListeners();
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      gpsError = 'إذن الموقع مرفوض نهائيًا. فعّله من الإعدادات.';
      notifyListeners();
      return false;
    }
    gpsError = null;
    return true;
  }

  /// Go online/offline. Before going online, verifies GPS is enabled and
  /// permission granted — fails gracefully with [gpsError] if not.
  ///
  /// Returns false (with [gpsError] populated) instead of throwing when the
  /// request fails. The previous version let the exception escape, so a
  /// rejected /captain/online call (e.g. 403 NOT_APPROVED) left `online`
  /// unchanged while the UI switch had already flipped — the captain saw
  /// themselves as online while the server had them offline and sent no rides.
  Future<bool> setOnline(bool value) async {
    if (value) {
      final ready = await checkGpsReady();
      if (!ready) return false;
    }
    try {
      // The server requires lat/lng when going online. Going offline should
      // still succeed even if a GPS fix cannot be obtained.
      Position? pos;
      try {
        pos = await _position();
        lastPosition = pos;
      } catch (_) {
        if (value) {
          gpsError = 'تعذّر تحديد موقعك. تأكد من تفعيل GPS.';
          notifyListeners();
          return false;
        }
      }

      await _post('/captain/online', {
        'online': value,
        if (pos != null) 'lat': pos.latitude,
        if (pos != null) 'lng': pos.longitude,
        'city': 'cairo',
      });
      online = value;
      gpsError = null;
      if (value) {
        _startLocationStream();
      } else {
        // Going offline must take the work off screen with it. Leaving the
        // cards up meant a captain could still tap accept on a trip the
        // server would now refuse (403 OFFLINE), and the countdown kept
        // running on offers they could no longer take.
        _stopLocationStream();
        offers = [];
        _declinedTripIds.clear();
        _bidTripIds.clear();
      }
      notifyListeners();
      if (value) {
        // Pull immediately rather than waiting for the next poll — the
        // captain just asked for work and expects to see it.
        unawaited(refreshOffers());
      }
      return true;
    } catch (e) {
      gpsError = e.toString().replaceAll('Exception:', '').trim();
      notifyListeners();
      return false;
    }
  }

  // -------------------------------------------------------------------
  // Location stream (single shared GPS subscription + adaptive accuracy)
  // -------------------------------------------------------------------

  /// GPS accuracy profiles. High accuracy + a tight distance filter is only
  /// worth the battery while a trip is active (accepted/arrived/in_progress)
  /// and the rider is watching the captain approach. With no active trip a
  /// coarser fix is plenty to keep the captain on the dispatch map, so we
  /// drop to medium accuracy and a wide filter and let the GPS radio rest.
  static LocationSettings get _idleLocationSettings => const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 50, // only wake the radio when the captain moves 50m
      );
  static LocationSettings get _tripLocationSettings => const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // precise tracking while on a trip
      );

  /// True while a trip is in a state that justifies high-accuracy GPS.
  bool get _hasActiveTrip {
    final status = activeTrip?['status'] as String?;
    return activeTrip != null &&
        ['assigned', 'accepted', 'arrived', 'in_progress'].contains(status);
  }

  bool _lifecyclePaused = false;

  void _startLocationStream() {
    _stopLocationStream();
    if (_lifecyclePaused) return; // app is backgrounded — stay off the radio
    final settings = _hasActiveTrip ? _tripLocationSettings : _idleLocationSettings;
    _positionStreamSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (Position pos) {
        // Remember the fix: the offers filter measures each pickup from here,
        // so a captain who has driven out of range of a queued request stops
        // being shown it without waiting for a server round-trip.
        lastPosition = pos;
        // Fan every fix out to the shared broadcast stream so the map camera
        // (and any other UI consumer) rides the SAME GPS subscription as the
        // server push below — one radio, two listeners.
        if (!_positionCtrl.isClosed) _positionCtrl.add(pos);
        if (online || activeTrip != null) {
          pushLocationCoordinates(pos.latitude, pos.longitude);
        }
      },
      onError: (_) {},
    );
  }

  void _stopLocationStream() {
    _positionStreamSub?.cancel();
    _positionStreamSub = null;
  }

  /// Re-evaluate the GPS accuracy profile after a trip-state transition. If
  /// the stream is running and the desired profile changed (idle ↔ trip),
  /// restart the stream with the new settings. A no-op when the stream is
  /// off (offline or backgrounded).
  void _syncLocationAccuracy() {
    if (_positionStreamSub == null || _lifecyclePaused) return;
    _startLocationStream();
  }

  Future<void> pushLocationCoordinates(double lat, double lng) async {
    if (!online && activeTrip == null) return;
    try {
      await _post('/captain/location', {
        'lat': lat,
        'lng': lng,
        'city': 'cairo',
        if (activeTrip != null) 'tripId': activeTrip!['id'],
      });
    } catch (_) {}
  }

  Future<void> pushLocation() async {
    if (!online && activeTrip == null) return;
    try {
      final pos = await _position();
      lastPosition = pos;
      await pushLocationCoordinates(pos.latitude, pos.longitude);
    } catch (_) {}
  }

  // -------------------------------------------------------------------
  // Search radius
  // -------------------------------------------------------------------

  /// Change how far out the captain wants work.
  ///
  /// Writes through in three places because all three matter: locally (so the
  /// choice survives a restart), to the server (so *dispatch* stops fanning
  /// out-of-range trips to this captain at all — inbox and FCM included), and
  /// straight into the current offers list (so the screen corrects itself
  /// immediately instead of on the next poll).
  Future<void> setSearchRadius(double km) async {
    if (km <= 0 || km == searchRadiusKm) return;
    searchRadiusKm = km;
    // Re-filter what is already on screen before anything is awaited.
    offers = offers.where(isWithinSearchRadius).toList();
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kSearchRadiusKey, km);

    _radiusPushInFlight = true;
    try {
      await _post('/captain/search-radius', {'radiusKm': km});
    } catch (_) {
      // The local filter still applies; the server just keeps offering a
      // wider net until the next successful write.
    } finally {
      _radiusPushInFlight = false;
    }

    await refreshOffers();
  }

  /// True when [offer]'s pickup is inside the captain's chosen radius.
  ///
  /// Measured from the live GPS fix when there is one, because the server's
  /// `captain_to_pickup_km` is derived from the last *pushed* position and
  /// can lag a moving captain by a minute. Anything we cannot measure is let
  /// through rather than hidden — a missing coordinate should not silently
  /// swallow work.
  bool isWithinSearchRadius(Map<String, dynamic> offer) {
    final lat = (offer['pickup_lat'] as num?)?.toDouble();
    final lng = (offer['pickup_lng'] as num?)?.toDouble();
    final pos = lastPosition;

    double? distanceKm;
    if (pos != null && lat != null && lng != null) {
      distanceKm =
          Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng) / 1000;
    } else {
      distanceKm = (offer['captain_to_pickup_km'] as num?)?.toDouble();
    }

    if (distanceKm == null) return true;
    return distanceKm <= searchRadiusKm;
  }

  // -------------------------------------------------------------------
  // Offers polling (REST backstop; the WebSocket inbox is primary)
  // -------------------------------------------------------------------

  /// REST polling cadence while the offers WebSocket is DOWN. Kept tight so
  /// a dropped socket does not leave the captain blind to new work.
  static const Duration _offersPollInterval = Duration(seconds: 8);

  /// REST polling cadence while the offers WebSocket is CONNECTED. The socket
  /// already pushes new offers in real time, so the poll degrades to a slow
  /// backstop that only re-syncs state the socket might have missed.
  static const Duration _offersPollIntervalWsUp = Duration(seconds: 60);

  Duration get _currentPollInterval =>
      offersWsStatus == 'connected' ? _offersPollIntervalWsUp : _offersPollInterval;

  void startOffersPolling() {
    _restartOffersTimer();
    refreshOffers();
    _connectOffersWs();
    _startApprovalPolling();
  }

  /// Arm the periodic /auth/me refresh that delivers admin approval decisions.
  /// Idempotent — re-arming is safe because the timer is cancelled first.
  void _startApprovalPolling() {
    _approvalPollTimer?.cancel();
    _approvalPollTimer = Timer.periodic(_approvalPollInterval, (_) async {
      if (token == null || _lifecyclePaused) return;
      try {
        await refreshMe();
      } catch (_) {}
    });
  }

  /// Stop the approval poll (logout / dispose).
  void _stopApprovalPolling() {
    _approvalPollTimer?.cancel();
    _approvalPollTimer = null;
  }

  /// (Re)arm the periodic REST poll at the cadence appropriate for the
  /// current socket state. Called on every WS status change so reconnects
  /// slow the poll down and drops speed it back up.
  void _restartOffersTimer() {
    offersTimer?.cancel();
    if (_lifecyclePaused) return; // app is backgrounded — no polling
    offersTimer = Timer.periodic(_currentPollInterval, (_) => refreshOffers());
  }

  Timer? _wsDebounce;

  void _connectOffersWs() {
    if (token == null) return;
    offersWs?.dispose();
    offersWs = OffersWebSocketService(
      baseUrl: baseUrl,
      token: token!,
      onStatus: (s) {
        // Debounce WS status changes — prevents UI flicker when the
        // connection rapidly reconnects/disconnects during network jitter.
        _wsDebounce?.cancel();
        _wsDebounce = Timer(const Duration(milliseconds: 600), () {
          final wasConnected = offersWsStatus == 'connected';
          offersWsStatus = s;
          // The poll cadence depends on socket health: connected → 60s
          // backstop, anything else → 8s REST fallback. Re-arm the timer on
          // every transition so a socket that flaps doesn't leave the cadence
          // stuck on the wrong side.
          if ((s == 'connected') != wasConnected) _restartOffersTimer();
          notifyListeners();
        });
      },
      onMessage: (msg) {
        final type = msg['type'] as String?;
        // Any inbox event (new offer, offer withdrawn, trip cancelled by the
        // rider, a bid the rider just accepted) means the offers list is
        // stale — refetch immediately rather than waiting out the poll
        // interval. For 'trip.assigned' that refetch is also what surfaces
        // the new active trip and fires [tripAssigned], which sends the
        // captain to the map.
        if (type == 'trip.offer' ||
            type == 'trip.cancelled' ||
            type == 'offer.withdrawn' ||
            type == 'trip.updated' ||
            type == 'trip.assigned' ||
            type == 'bid.accepted') {
          refreshOffers();
        }
      },
    )..connect();
  }

  /// Opens (or re-opens) the live room socket for [tripId]. Idempotent —
  /// repeated calls for the same trip are a no-op.
  void _connectTripWs(String tripId) {
    if (token == null) return;
    if (_tripWs?.currentTripId == tripId) return;
    _tripWsSub?.cancel();
    _tripWs?.dispose();
    _tripWs = CaptainTripWebSocketService(
      baseUrl: baseUrl,
      tripId: tripId,
      token: token!,
    );
    _tripWsSub = _tripWs!.messages.listen(_onTripWsEvent);
    _tripWs!.connect();
  }

  void _disconnectTripWs() {
    _tripWsSub?.cancel();
    _tripWsSub = null;
    _tripWs?.dispose();
    _tripWs = null;
  }

  void _onTripWsEvent(Map<String, dynamic> ev) {
    final type = ev['type'] as String?;

    // Fan the raw event out to UI subscribers (chat screen, trip panel) so
    // they can react without a poll round-trip.
    if (!_tripEventsCtrl.isClosed) _tripEventsCtrl.add(ev);

    if (type == 'trip.updated' && ev['trip'] is Map) {
      final updated = Map<String, dynamic>.from(ev['trip'] as Map);
      final current = activeTrip;
      if (current != null && updated['id'] == current['id']) {
        final status = updated['status'] as String?;
        if (['assigned', 'arrived', 'in_progress'].contains(status)) {
          activeTrip = updated;
        } else {
          // Completed or cancelled on the other side: clear immediately so the
          // captain is never acting on a dead trip, and re-sync the queue.
          activeTrip = null;
          _announcedTripId = null;
          stopInAppNavigation();
          _disconnectTripWs();
          unawaited(refreshOffers());
        }
        _syncLocationAccuracy();
        notifyListeners();
      }
    } else if (type == 'chat.message') {
      // Nothing else to do here: the event was already fanned out above and
      // the chat screen (if open) refetches on it. When the screen is closed
      // the unread count is surfaced via the panel's badge.
      notifyListeners();
    }
  }

  Future<void> refreshOffers() async {
    if (token == null) return;
    // An offline captain has no offers by definition — the server already
    // returns an empty list, so skip the request entirely and make sure
    // nothing stale is left on screen.
    if (!online) {
      if (offers.isNotEmpty) {
        offers = [];
        notifyListeners();
      }
      return;
    }
    try {
      final res = await _get('/captain/offers');
      final trips = (res['trips'] as List?)?.whereType<Map>() ?? [];
      offers = trips
          .map((e) => Map<String, dynamic>.from(e))
          .where((o) => !_declinedTripIds.contains(o['id']))
          // Radius guard. The server filters too, but this keeps an older
          // API build (or a captain who has driven since the last location
          // push) from putting an out-of-range trip back on the tab badge.
          .where(isWithinSearchRadius)
          .toList();

      final mine = await _get('/trips');
      final all = (mine['trips'] as List?)?.whereType<Map>() ?? [];
      final active = all
          .map((e) => Map<String, dynamic>.from(e))
          .where((t) {
            final s = t['status'] as String?;
            return t['captain_id'] == user?['id'] &&
                ['assigned', 'arrived', 'in_progress'].contains(s);
          })
          .toList();
      final previousTripId = activeTrip?['id'] as String?;
      final hadActiveTrip = _hasActiveTrip;
      activeTrip = active.isNotEmpty ? active.first : null;

      // Keep the room socket in step with the trip actually on screen: open
      // it the moment a trip is assigned, close it the moment there is none.
      final newTripId = activeTrip?['id'] as String?;
      if (newTripId != null) {
        if (newTripId != previousTripId) {
          _connectTripWs(newTripId);
          // A trip appeared that was not here a moment ago — most often the
          // rider just accepted this captain's price edit. Tell the shell so
          // it opens the map instead of leaving them on the requests list.
          _announceTripAssigned(activeTrip!);
        } else if (_tripWs == null) {
          // The socket can die silently: reconnect backoff gives up after a
          // long outage, and _connectTripWs is a no-op for the same tripId,
          // so without this check a captain whose app briefly lost network
          // would stay on the 8s poll for the rest of the trip — the visible
          // "الرسايل بتوصل متأخر" the room socket exists to kill.
          _connectTripWs(newTripId);
        }
      } else {
        _disconnectTripWs();
        // Nothing active any more: the next assignment is a fresh event.
        _announcedTripId = null;
      }

      // The active trip changed (assigned → none, none → assigned, etc.):
      // re-evaluate the GPS accuracy profile so the radio matches the work.
      if (_hasActiveTrip != hadActiveTrip) _syncLocationAccuracy();

      // Clear any stale error from a previous failed poll, otherwise the UI
      // keeps showing an error banner long after connectivity is restored.
      error = null;
      notifyListeners();
    } catch (e) {
      error = e.toString().replaceAll('Exception:', '').trim();
      notifyListeners();
    }
  }

  /// Accept the rider's proposed fare as-is. Assigns the trip immediately.
  ///
  /// The server enforces the same online rule (403 OFFLINE), but checking here
  /// turns a wasted round-trip into an instant, correctly-worded refusal —
  /// and closes the race where the captain toggles offline while a card is
  /// still on screen.
  Future<void> accept(String tripId) async {
    if (!online) throw Exception(offlineActionMessage);
    final res = await _post('/trips/$tripId/accept');
    activeTrip = Map<String, dynamic>.from(res['trip'] as Map);
    offers.removeWhere((o) => o['id'] == tripId);
    // The captain now has a trip; previously dismissed offers are irrelevant.
    _declinedTripIds.clear();
    // Open the live room immediately so rider cancellations and chat reach
    // this screen in real time.
    _connectTripWs(tripId);
    // A trip just started: escalate the GPS to high-accuracy tracking.
    _syncLocationAccuracy();
    // Same destination as a won bid — the job is driven on the map.
    _announceTripAssigned(activeTrip!);
    notifyListeners();
    // Report position immediately so the rider sees the captain moving without
    // waiting for the next stream tick.
    await pushLocation();
  }

  /// Shown whenever a trip action is attempted while offline. Matches the
  /// server's own Arabic copy so the captain sees one consistent reason.
  static const offlineActionMessage = 'يجب أن تكون متصلاً لاستقبال الرحلات';

  /// Submit a counter-offer (bid) for [tripId] at [amount] EGP.
  ///
  /// Endpoint is `POST /trips/:id/bid` with `{counterPrice}` — note the
  /// singular path and the field name; both are what `createBidSchema`
  /// validates server-side (1..10000).
  ///
  /// Unlike [accept] this does *not* assign the trip: the rider still has to
  /// choose the bid, so the offer stays in the list. It is marked locally as
  /// bid-on so the card can show that the captain already responded rather
  /// than inviting a duplicate bid.
  Future<void> submitBid(String tripId, double amount) async {
    if (!online) throw Exception(offlineActionMessage);
    await _post('/trips/$tripId/bid', {'counterPrice': amount});
    _bidTripIds[tripId] = amount;
    notifyListeners();
  }

  /// Trip id → the fare this captain last bid on it.
  final Map<String, double> _bidTripIds = {};

  double? bidFor(String tripId) => _bidTripIds[tripId];
  bool hasBidOn(String tripId) => _bidTripIds.containsKey(tripId);

  /// Dismiss an offer locally.
  ///
  /// There is no POST /trips/:id/decline on the server — a captain declines
  /// simply by not accepting, and the trip stays available to others. The old
  /// implementation fired that request and swallowed the 404, wasting a
  /// round-trip on every decline. The id is also remembered so the next
  /// refreshOffers() poll does not immediately re-add the card the captain
  /// just dismissed.
  final Set<String> _declinedTripIds = {};

  void decline(String tripId) {
    _declinedTripIds.add(tripId);
    offers.removeWhere((o) => o['id'] == tripId);
    notifyListeners();
  }

  Future<void> arrived() async {
    if (activeTrip == null) return;
    final res = await _post('/trips/${activeTrip!['id']}/arrived');
    activeTrip = Map<String, dynamic>.from(res['trip'] as Map);
    _syncLocationAccuracy();
    notifyListeners();
  }

  Future<void> startTrip() async {
    if (activeTrip == null) return;
    final res = await _post('/trips/${activeTrip!['id']}/start');
    activeTrip = Map<String, dynamic>.from(res['trip'] as Map);
    _syncLocationAccuracy();
    notifyListeners();
  }

  Future<void> complete() async {
    if (activeTrip == null) return;
    final res = await _post('/trips/${activeTrip!['id']}/complete');
    activeTrip = Map<String, dynamic>.from(res['trip'] as Map);
    stopInAppNavigation();
    _disconnectTripWs();
    // Trip is over: drop the GPS back to the low-power idle profile.
    _syncLocationAccuracy();
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // App lifecycle (pause the radio + polling while backgrounded)
  // -------------------------------------------------------------------

  /// Called by the main shell's WidgetsBindingObserver. Backgrounding the app
  /// pauses the GPS stream and the offers poll — the biggest battery drains —
  /// and foregrounding restores them. FCM still wakes the app for real work.
  void handleAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        if (_lifecyclePaused) return;
        _lifecyclePaused = true;
        _stopLocationStream();
        offersTimer?.cancel();
        offersTimer = null;
        break;
      case AppLifecycleState.resumed:
        if (!_lifecyclePaused) return;
        _lifecyclePaused = false;
        // Restore the GPS stream (if the captain is online / on a trip) and
        // re-arm the poll, then re-sync immediately so anything missed while
        // backgrounded shows up without waiting for the next tick.
        if (online || activeTrip != null) _startLocationStream();
        _restartOffersTimer();
        unawaited(refreshOffers());
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<Map<String, dynamic>> earnings() => _get('/captain/earnings');

  Future<void> registerDeviceToken(String fcm) async {
    fcmToken = fcm;
    if (token == null) return;
    try {
      await _post('/user/device', {'token': fcm, 'platform': 'android'});
    } catch (_) {}
  }

  void setLocale(Locale l) {
    locale = l;
    notifyListeners();
  }

  /// SharedPreferences key for the captain's chosen theme. Stored as the enum
  /// name ('light' | 'dark' | 'system') so it round-trips without depending on
  /// a fragile ordinal index.
  static const _kThemeModeKey = 'themeMode';

  void setThemeMode(ThemeMode m) {
    themeMode = m;
    notifyListeners();
    // Persist out-of-band so the setter stays synchronous for its UI callers.
    // Nothing wrote this before, so every relaunch reset the app to
    // ThemeMode.system regardless of what the captain had picked.
    unawaited(_persistThemeMode(m));
  }

  Future<void> _persistThemeMode(ThemeMode m) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, m.name);
  }

  Future<void> logout() async {
    _stopLocationStream();
    _stopApprovalPolling();
    offersTimer?.cancel();
    offersTimer = null;
    _wsDebounce?.cancel();
    offersWs?.dispose();
    offersWs = null;
    offersWsStatus = 'idle';
    _disconnectTripWs();
    token = null;
    user = null;
    captain = null;
    activeTrip = null;
    _announcedTripId = null;
    offers = [];
    online = false;
    error = null;
    gpsError = null;
    lastPosition = null;
    _declinedTripIds.clear();
    _bidTripIds.clear();
    navigationTarget = null;
    final prefs = await SharedPreferences.getInstance();
    // Signing out ends the session, not the person's display preference.
    // Remove only the keys this class owns instead of prefs.clear() (which
    // used to wipe the saved theme too), and drop the tokens from secure
    // storage explicitly.
    await _secureStorage.delete(key: 'token');
    await _secureStorage.delete(key: 'refreshToken');
    await prefs.remove('user');
    notifyListeners();
  }

  @override
  void dispose() {
    _stopLocationStream();
    _stopApprovalPolling();
    _positionCtrl.close();
    offersTimer?.cancel();
    _wsDebounce?.cancel();
    offersWs?.dispose();
    _disconnectTripWs();
    _tripEventsCtrl.close();
    _navigationStartCtrl.close();
    _tripAssignedCtrl.close();
    super.dispose();
  }
}
