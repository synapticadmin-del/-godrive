import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_shared/flutter_shared.dart';

class AppState extends ChangeNotifier {
  AppState({required this.role});

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

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token');
    final raw = prefs.getString('user');
    if (raw != null) user = jsonDecode(raw) as Map<String, dynamic>;
    if (token != null) {
      await FcmService.init();
    }
    loading = false;
    notifyListeners();
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
              return await reqFn(); // Retry original request with new token
            }
          }
        } catch (_) {}
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
    final refresh = res['refreshToken'] as String?;
    user = Map<String, dynamic>.from(res['user'] as Map);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token!);
    if (refresh != null) await prefs.setString('refreshToken', refresh);
    await prefs.setString('user', jsonEncode(user));
    await FcmService.init();
    notifyListeners();
  }

  Future<void> loginWithEmail({required String email, required String password}) async {
    error = null;
    final res = await _post('/auth/login', {'email': email, 'password': password});
    token = (res['accessToken'] ?? res['token']) as String?;
    final refresh = res['refreshToken'] as String?;
    user = Map<String, dynamic>.from(res['user'] as Map);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token!);
    if (refresh != null) await prefs.setString('refreshToken', refresh);
    await prefs.setString('user', jsonEncode(user));
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token!);
    await prefs.setString('user', jsonEncode(user));
    await FcmService.init();
    notifyListeners();
  }

  Future<void> logout() async {
    token = null;
    user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user');
    await prefs.remove('refreshToken');
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

  Future<Map<String, dynamic>> createTrip({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? pickupAddress,
    String? dropoffAddress,
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
    String? email,
    String? phone,
    String? avatarUrl,
  }) async {
    user = {
      ...(user ?? {}),
      if (name != null && name.isNotEmpty) 'name': name,
      if (email != null && email.isNotEmpty) 'email': email,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user', jsonEncode(user));
    notifyListeners();
  }

  /// Wallet balance (from backend). Null until first fetch.
  double? walletBalance;

  Future<Map<String, dynamic>> fetchWallet() async {
    final res = await _get('/wallet');
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
