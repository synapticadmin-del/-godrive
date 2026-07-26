import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_shared/flutter_shared.dart';

class AppState extends ChangeNotifier {
  AppState({required this.role});

  // Persistence keys. These names are part of the app's on-disk contract:
  // renaming them would silently sign out every rider who already has a
  // session stored from a previous build, so they stay fixed.
  static const String _kAccessToken = 'token';
  static const String _kRefreshToken = 'refreshToken';
  static const String _kUserData = 'user';

  final String role;
  bool loading = true;
  String? token;
  Map<String, dynamic>? user;
  String? error;

  /// Default to Arabic (Egypt) — Egyptian market; English as secondary.
  Locale locale = const Locale('ar', 'EG');
  ThemeMode themeMode = ThemeMode.system;

  /// FCM token currently registered with backend.
  String? fcmToken;

  /// Production API (Cloudflare). For local API use:
  /// return kIsWeb ? 'http://127.0.0.1:8787' : 'http://10.0.2.2:8787';
  static String get defaultBaseUrl {
    return 'https://api.synapticstudio.tech';
  }

  String baseUrl = defaultBaseUrl;

  /// Decodes the `exp` claim of a JWT without verifying its signature.
  ///
  /// Signature verification is the API's job — the client only needs to know
  /// whether a stored token is already past its expiry so it can avoid
  /// restoring a session that the server is guaranteed to reject.
  ///
  /// Returns `null` when the token is malformed or carries no usable `exp`,
  /// which callers treat as "can't prove it's expired" rather than "expired".
  static DateTime? _jwtExpiry(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;

      // JWTs use base64url without padding; normalize before decoding.
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return null;

      final exp = payload['exp'];
      if (exp is! num) return null;

      return DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
    } catch (_) {
      // A token we cannot parse is not provably expired — let the API decide.
      return null;
    }
  }

  /// True when [jwt] carries an `exp` claim that has already passed.
  ///
  /// A small skew allowance keeps a token that is seconds from expiring from
  /// being restored only to fail on the very next request.
  static bool isTokenExpired(String? jwt) {
    if (jwt == null || jwt.isEmpty) return true;
    final expiry = _jwtExpiry(jwt);
    if (expiry == null) return false; // opaque/unparseable — treat as usable
    return DateTime.now().toUtc().isAfter(
          expiry.subtract(const Duration(seconds: 30)),
        );
  }

  /// Restores a previously persisted session so relaunching the app does not
  /// force the rider back through the login screen.
  ///
  /// The rules that matter here:
  ///  * A stored access token that is still valid restores the session
  ///    immediately — `main.dart` sees a non-null [token] and goes straight to
  ///    `HomeScreen`, skipping `LoginScreen`.
  ///  * An expired access token is not thrown away while a refresh token
  ///    exists; we spend one round trip trying to mint a new one.
  ///  * Profile refresh is best-effort. If the device is offline at launch the
  ///    cached [user] still stands, so a rider in a lift or a tunnel stays
  ///    logged in instead of being ejected by a failed network call.
  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_kAccessToken);

    final raw = prefs.getString(_kUserData);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) user = Map<String, dynamic>.from(decoded);
      } catch (_) {
        // Corrupt cache should never be fatal at launch.
        await prefs.remove(_kUserData);
      }
    }

    await FcmService.init(onToken: registerDeviceToken);

    if (token != null && isTokenExpired(token)) {
      // Access token has lapsed. Try the refresh token before giving up —
      // only a failed refresh should cost the rider their session.
      final refreshed = await _refreshAccessToken();
      if (!refreshed) {
        await _clearSession();
        loading = false;
        notifyListeners();
        return;
      }
    }

    if (token != null) {
      // Best-effort revalidation; offline launches keep the cached profile.
      await fetchProfile();
    }

    loading = false;
    notifyListeners();
  }

  /// Exchanges the stored refresh token for a fresh access token.
  ///
  /// Returns true when [token] now holds a usable access token. Kept separate
  /// from the 401 interceptor so launch-time refresh and mid-session refresh
  /// share one implementation.
  Future<bool> _refreshAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_kRefreshToken);
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );
      if (res.statusCode >= 400) return false;

      final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
      if (data is! Map) return false;

      final fresh = (data['accessToken'] ?? data['token']) as String?;
      if (fresh == null || fresh.isEmpty) return false;

      token = fresh;
      await prefs.setString(_kAccessToken, fresh);

      // Some backends rotate the refresh token on each use; persist if sent.
      final rotated = data['refreshToken'] as String?;
      if (rotated != null && rotated.isNotEmpty) {
        await prefs.setString(_kRefreshToken, rotated);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Persists a freshly issued session. Single writer for all three keys so
  /// login, OTP verification and registration cannot drift apart.
  Future<void> _persistSession({
    required String? accessToken,
    String? refreshToken,
    Map<String, dynamic>? userData,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (accessToken != null && accessToken.isNotEmpty) {
      await prefs.setString(_kAccessToken, accessToken);
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await prefs.setString(_kRefreshToken, refreshToken);
    }
    if (userData != null) {
      await prefs.setString(_kUserData, jsonEncode(userData));
    }
  }

  /// Drops every trace of the session from memory and disk.
  Future<void> _clearSession() async {
    token = null;
    user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kRefreshToken);
    await prefs.remove(_kUserData);
  }

  Future<Map<String, dynamic>?> fetchProfile() async {
    if (token == null) return null;
    try {
      final res = await _get('/auth/me');
      if (res['user'] != null) {
        final localAvatar = user?['avatarUrl'];
        user = {
          ...Map<String, dynamic>.from(res['user'] as Map),
          if (localAvatar is String && localAvatar.isNotEmpty) 'avatarUrl': localAvatar,
        };
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kUserData, jsonEncode(user));
        notifyListeners();
      }
      return res;
    } catch (_) {
      return null;
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
      // Shares one refresh implementation with launch-time restore so both
      // paths handle token rotation identically.
      if (await _refreshAccessToken()) {
        return await reqFn(); // Retry original request with the new token
      }
      await logout(); // Safe auto-logout on refresh failure
      throw Exception('Session expired. Please log in again.');
    }
    return res;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res = await _executeWithAuthInterceptor(() => http.post(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
          body: jsonEncode(body),
        ));
    final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
    if (res.statusCode >= 400) {
      throw Exception(data is Map && data['error'] != null ? data['error'] : 'HTTP ${res.statusCode}');
    }
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> _patch(String path, Map<String, dynamic> body) async {
    final res = await _executeWithAuthInterceptor(() => http.patch(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
          body: jsonEncode(body),
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
  Future<Map<String, dynamic>> apiPost(String path, [Map<String, dynamic>? body]) => _post(path, body ?? {});
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
    error = null;
    notifyListeners();
    try {
      final res = await _post('/auth/request-otp', {
        'email': email,
        'role': role,
        if (name != null) 'name': name,
      });
      return res['devCode'] as String?;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> verifyOtp(String email, String code) async {
    error = null;
    final res = await _post('/auth/verify-otp', {'email': email, 'code': code});
    token = (res['accessToken'] ?? res['token']) as String?;
    user = Map<String, dynamic>.from(res['user'] as Map);
    await _persistSession(
      accessToken: token,
      refreshToken: res['refreshToken'] as String?,
      userData: user,
    );
    await FcmService.init();
    notifyListeners();
  }

  Future<void> loginWithEmail({required String email, required String password}) async {
    error = null;
    final res = await _post('/auth/login', {'email': email, 'password': password});
    token = (res['accessToken'] ?? res['token']) as String?;
    user = Map<String, dynamic>.from(res['user'] as Map);
    await _persistSession(
      accessToken: token,
      refreshToken: res['refreshToken'] as String?,
      userData: user,
    );
    await FcmService.init();
    notifyListeners();
  }

  Future<void> registerWithEmail({
    required String email,
    required String password,
    required String name,
    required String phone,
  }) async {
    error = null;
    final res = await _post('/auth/register', {
      'email': email,
      'password': password,
      'name': name,
      'phone': phone,
      'role': 'rider',
    });
    token = (res['accessToken'] ?? res['token']) as String?;
    user = Map<String, dynamic>.from(res['user'] as Map);
    // Registration returns a refresh token too; persisting it here means a
    // brand-new rider gets the same durable session as one who signs in.
    await _persistSession(
      accessToken: token,
      refreshToken: res['refreshToken'] as String?,
      userData: user,
    );
    await FcmService.init();
    notifyListeners();
  }

  Future<void> logout() async {
    await _clearSession();
    notifyListeners();
  }

  Future<Map<String, dynamic>> estimateTrip({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  }) {
    return _post('/trips/estimate', {
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'dropoffLat': dropoffLat,
      'dropoffLng': dropoffLng,
      'city': 'cairo',
    });
  }

  /// Creates a trip request.
  ///
  /// [vehicleTypeId] is the car class the rider picked (economy / comfort /
  /// xl). `POST /trips` persists it as `vehicle_type_id`; omitting it stores
  /// NULL, which is why the selection has to be threaded through rather than
  /// held only in the sheet's local state.
  Future<Map<String, dynamic>> createTrip({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? pickupAddress,
    String? dropoffAddress,
    String? vehicleTypeId,
  }) {
    return _post('/trips', {
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'dropoffLat': dropoffLat,
      'dropoffLng': dropoffLng,
      'pickupAddress': pickupAddress,
      'dropoffAddress': dropoffAddress,
      'city': 'cairo',
      'paymentMethod': 'cash',
      if (vehicleTypeId != null) 'vehicleTypeId': vehicleTypeId,
    });
  }

  Future<Map<String, dynamic>> getTrip(String id) => _get('/trips/$id');

  Future<void> cancelTrip(String id) async {
    await _post('/trips/$id/cancel', {'reason': 'user_cancelled'});
  }

  Future<void> rateTrip(String id, int score) async {
    await _post('/trips/$id/rate', {'score': score});
  }

  /// Register an FCM token with the backend so trip push notifications reach
  /// this device. Mirrors `POST /user/device` on the API.
  Future<void> registerDeviceToken(String fcmToken) async {
    this.fcmToken = fcmToken;
    if (token == null) return; // not logged in yet — token will retry on login
    try {
      await _post('/user/device', {'token': fcmToken, 'platform': 'android'});
    } catch (_) {
      // best-effort; will refresh later
    }
  }

  void setLocale(Locale newLocale) {
    locale = newLocale;
    notifyListeners();
  }

  void toggleLanguage() {
    if (locale.languageCode == 'ar') {
      locale = const Locale('en', 'US');
    } else {
      locale = const Locale('ar', 'EG');
    }
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    notifyListeners();
  }

  void toggleTheme() {
    if (themeMode == ThemeMode.dark) {
      themeMode = ThemeMode.light;
    } else {
      themeMode = ThemeMode.dark;
    }
    notifyListeners();
  }

  Future<void> updateUserProfile({
    String? name,
    String? phone,
    String? avatarUrl,
  }) async {
    final payload = <String, dynamic>{
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
    };

    var updatedUser = Map<String, dynamic>.from(user ?? const {});
    if (payload.isNotEmpty) {
      final res = await _patch('/user/profile', payload);
      final serverUser = res['user'];
      if (serverUser is Map) {
        updatedUser = Map<String, dynamic>.from(serverUser);
      }
    }

    user = {
      ...updatedUser,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserData, jsonEncode(user));
    notifyListeners();
  }

  /// Wallet balance (from backend). Null until first fetch.
  double? walletBalance;

  Future<Map<String, dynamic>> fetchWallet() async {
    final res = await _get('/user/wallet');
    walletBalance = (res['balance'] as num?)?.toDouble();
    notifyListeners();
    return res;
  }

  /// Returns a Paymob iframe URL (server-side intention). The screen opens it
  /// in a WebView and the backend webhook credits the wallet on success.
  Future<String> topUpViaPaymob(double amountEgp) async {
    final res = await _post('/payments/paymob/intention', {
      'amount': amountEgp,
      'purpose': 'wallet_topup',
    });
    return (res['iframeUrl'] ?? res['iframe_url']) as String;
  }

  /// Trip sharing — builds a public tracking URL (no auth needed to view).
  String shareTripUrl(String tripId) => '$baseUrl/trips/$tripId/track';
}
