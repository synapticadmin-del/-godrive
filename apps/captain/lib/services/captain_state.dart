import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'offers_ws.dart';

class CaptainState extends ChangeNotifier {
  bool loading = true;
  bool online = false;
  String? token;
  Map<String, dynamic>? user;
  Map<String, dynamic>? captain;
  Map<String, dynamic>? activeTrip;
  List<Map<String, dynamic>> offers = [];
  String? error;
  
  StreamSubscription<Position>? _positionStreamSub;
  Timer? offersTimer;
  OffersWebSocketService? offersWs;
  String offersWsStatus = 'idle';

  Locale locale = const Locale('ar', 'EG');
  ThemeMode themeMode = ThemeMode.system;
  String? fcmToken;

  static String get defaultBaseUrl {
    return 'https://api.synapticstudio.tech';
  }

  String baseUrl = defaultBaseUrl;

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token');
    final raw = prefs.getString('user');
    if (raw != null) user = jsonDecode(raw) as Map<String, dynamic>;
    loading = false;
    notifyListeners();
    if (token != null) {
      FcmService.init();
      await refreshMe();
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
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refreshToken');
      if (refreshToken != null) {
        try {
          final refreshRes = await http.post(
            Uri.parse('$baseUrl/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refreshToken}),
          );
          if (refreshRes.statusCode < 400) {
            final data = jsonDecode(refreshRes.body);
            token = (data['accessToken'] ?? data['token']) as String?;
            if (token != null) {
              await prefs.setString('token', token!);
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
    final res = await _executeWithAuthInterceptor(() => http.post(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
          body: jsonEncode(body ?? {}),
        ));
    final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
    if (res.statusCode >= 400) {
      throw Exception(data is Map && data['error'] != null ? data['error'] : 'HTTP ${res.statusCode}');
    }
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await _executeWithAuthInterceptor(() => http.get(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
        ));
    final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
    if (res.statusCode >= 400) {
      throw Exception(data is Map && data['error'] != null ? data['error'] : 'HTTP ${res.statusCode}');
    }
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> apiGet(String path) => _get(path);
  Future<Map<String, dynamic>> apiPost(String path, [Map<String, dynamic>? body]) => _post(path, body);
  Future<Map<String, dynamic>> apiDelete(String path) async {
    final res = await _executeWithAuthInterceptor(() => http.delete(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
        ));
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
    await prefs.setString('token', token!);
    if (refresh != null) await prefs.setString('refreshToken', refresh);
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
    await prefs.setString('token', token!);
    if (refresh != null) await prefs.setString('refreshToken', refresh);
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
    await prefs.setString('token', token!);
    await prefs.setString('user', jsonEncode(user));
    notifyListeners();
    startOffersPolling();
  }

  Future<void> refreshMe() async {
    final res = await _get('/auth/me');
    user = Map<String, dynamic>.from(res['user'] as Map);
    captain = res['captain'] == null ? null : Map<String, dynamic>.from(res['captain'] as Map);
    online = captain?['is_online'] == 1;
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

  Future<Position> _position() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return Geolocator.getCurrentPosition();
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
  Future<bool> setOnline(bool value) async {
    if (value) {
      final ready = await checkGpsReady();
      if (!ready) return false;
    }
    final pos = await _position();
    await _post('/captain/online', {
      'online': value,
      'lat': pos.latitude,
      'lng': pos.longitude,
      'city': 'cairo',
    });
    online = value;
    notifyListeners();
    if (value) {
      _startLocationStream();
    } else {
      _stopLocationStream();
    }
    return true;
  }

  void _startLocationStream() {
    _stopLocationStream();
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Only send update when captain moves 10 meters
    );
    _positionStreamSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position pos) {
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
      await pushLocationCoordinates(pos.latitude, pos.longitude);
    } catch (_) {}
  }

  void startOffersPolling() {
    offersTimer?.cancel();
    offersTimer = Timer.periodic(const Duration(seconds: 20), (_) => refreshOffers());
    refreshOffers();
    _connectOffersWs();
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
        _wsDebounce = Timer(const Duration(milliseconds: 1500), () {
          offersWsStatus = s;
          notifyListeners();
        });
      },
      onMessage: (msg) {
        final type = msg['type'] as String?;
        if (type == 'trip.offer') {
          refreshOffers();
        }
      },
    )..connect();
  }

  Future<void> refreshOffers() async {
    if (token == null) return;
    try {
      final res = await _get('/captain/offers');
      final trips = (res['trips'] as List?)?.cast<Map>() ?? [];
      offers = trips.map((e) => Map<String, dynamic>.from(e)).toList();

      final mine = await _get('/trips');
      final all = (mine['trips'] as List?)?.cast<Map>() ?? [];
      final active = all.cast<Map<String, dynamic>>().where((t) {
        final s = t['status'] as String?;
        return t['captain_id'] == user?['id'] &&
            ['assigned', 'arrived', 'in_progress'].contains(s);
      }).toList();
      activeTrip = active.isNotEmpty ? active.first : null;
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> accept(String tripId) async {
    final res = await _post('/trips/$tripId/accept');
    activeTrip = Map<String, dynamic>.from(res['trip'] as Map);
    notifyListeners();
    await pushLocation();
  }

  Future<void> arrived() async {
    if (activeTrip == null) return;
    final res = await _post('/trips/${activeTrip!['id']}/arrived');
    activeTrip = Map<String, dynamic>.from(res['trip'] as Map);
    notifyListeners();
  }

  Future<void> startTrip() async {
    if (activeTrip == null) return;
    final res = await _post('/trips/${activeTrip!['id']}/start');
    activeTrip = Map<String, dynamic>.from(res['trip'] as Map);
    notifyListeners();
  }

  Future<void> complete() async {
    if (activeTrip == null) return;
    final res = await _post('/trips/${activeTrip!['id']}/complete');
    activeTrip = Map<String, dynamic>.from(res['trip'] as Map);
    notifyListeners();
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

  void setThemeMode(ThemeMode m) {
    themeMode = m;
    notifyListeners();
  }

  Future<void> logout() async {
    _stopLocationStream();
    offersTimer?.cancel();
    offersWs?.dispose();
    offersWs = null;
    token = null;
    user = null;
    captain = null;
    activeTrip = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _stopLocationStream();
    offersTimer?.cancel();
    _wsDebounce?.cancel();
    offersWs?.dispose();
    super.dispose();
  }
}
