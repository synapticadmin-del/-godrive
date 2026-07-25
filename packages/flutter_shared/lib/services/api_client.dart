import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({required this.baseUrl, this.token});

  final String baseUrl;
  String? token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final res = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> get(String path) async {
    final res = await http.get(Uri.parse('$baseUrl$path'), headers: _headers);
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    final data = jsonDecode(res.body.isEmpty ? '{}' : res.body);
    if (res.statusCode >= 400) {
      throw Exception(data is Map && data['error'] != null ? data['error'] : 'HTTP ${res.statusCode}');
    }
    return Map<String, dynamic>.from(data as Map);
  }
}
