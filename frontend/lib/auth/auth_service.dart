import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  // Backend URL selection:
  // - If `--dart-define=BACKEND_URL` is provided, use it.
  // - If running on web, default to `http://localhost:8000`.
  // - Otherwise (Android emulator) use `http://10.0.2.2:8000`.
  static String get backendUrl {
    const env = String.fromEnvironment('BACKEND_URL', defaultValue: '');
    if (env.isNotEmpty) return env;
    if (kIsWeb) return 'http://localhost:8000';
    return 'http://10.0.2.2:8000';
  }

  static Future<Map<String, dynamic>> signup(
    String firstName,
    String lastName,
    String email,
    String phone,
    String password,
  ) async {
    final uri = Uri.parse('$backendUrl/signup');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'phone': phone,
        'password': password,
      }),
    );
    return _process(res);
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final uri = Uri.parse('$backendUrl/login');
    try {
      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 15));

      print('[AuthService] POST $uri -> ${res.statusCode}');
      print('[AuthService] response body: ${res.body}');

      final data = _process(res);

      // _process returns {'statusCode': ..., 'body': parsed}
      if (res.statusCode == 200) {
        final body = data['body'];
        String? token;
        if (body is Map && body['token'] != null) {
          token = body['token'].toString();
        }
        if (token != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', token);
        } else {
          print('[AuthService] login: no token found in response body');
        }
      }

      return data;
    } catch (e, st) {
      print('[AuthService] login error: $e\n$st');
      return {
        'statusCode': 0,
        'body': {'message': 'Network error: $e'},
      };
    }
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final uri = Uri.parse('$backendUrl/forgot-password');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    return _process(res);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Map<String, dynamic> _process(http.Response res) {
    try {
      final parsed = jsonDecode(res.body) as Map<String, dynamic>;
      return {'statusCode': res.statusCode, 'body': parsed};
    } catch (e) {
      return {
        'statusCode': res.statusCode,
        'body': {'message': res.body},
      };
    }
  }
}
