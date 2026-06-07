import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService extends ChangeNotifier {
  // ── Connection Logic ──────────────────────────────────────────
  String get _baseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000';
    return 'http://10.0.2.2:8000'; // Default for Android Emulators
  }

  String? _token;
  String? _userRole;
  String? _userEmail;
  bool _isLoading = false;

  bool get isAuthenticated => _token != null;
  bool get isAdmin => _userRole == "ADMIN";
  bool get isLoading => _isLoading;
  String? get userEmail => _userEmail;
  String? get token => _token;

  AuthService() {
    _loadSession();
  }

  Future<bool> register({
    required String email,
    required String password,
    String role = "APPLICANT",
  }) async {
    _setLoading(true);
    try {
      final url = Uri.parse("$_baseUrl/register");
      debugPrint("API CALL: POST $url");

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": email,
          "password": password,
          "role": role,
        }),
      ).timeout(const Duration(seconds: 15));

      debugPrint("API RESPONSE: ${response.statusCode}");
      if (response.statusCode == 200) {
        return true;
      } else {
        final err = jsonDecode(response.body)['detail'] ?? "Registration failed";
        throw Exception(err);
      }
    } on TimeoutException {
      debugPrint("AUTH ERROR: Register request timed out");
      throw Exception(
          'Cannot connect to server. Please ensure the backend is running and try again.');
    } catch (e) {
      debugPrint("AUTH ERROR: $e");
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _setLoading(true);
    try {
      final url = Uri.parse("$_baseUrl/login");
      debugPrint("API CALL: POST $url");

      final response = await http.post(
        url,
        body: {
          "username": email,
          "password": password,
        },
      ).timeout(const Duration(seconds: 30));

      debugPrint("API RESPONSE: ${response.statusCode}");
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['access_token'];
        _userRole = data['role'];
        _userEmail = data['email'];

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', _token!);
        await prefs.setString('role', _userRole!);
        await prefs.setString('email', _userEmail!);

        notifyListeners();
        return true;
      } else {
        final err = jsonDecode(response.body)['detail'] ?? "Login failed";
        throw Exception(err);
      }
    } on TimeoutException {
      debugPrint("AUTH ERROR: Login request timed out");
      throw Exception('Cannot connect to server. Please ensure the backend is running and try again.');
    } catch (e) {
      debugPrint("AUTH ERROR: $e");
      if (e is Exception) rethrow;
      throw Exception(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    _token = null;
    _userRole = null;
    _userEmail = null;
    _isLoading = false; // Reset loading state
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    notifyListeners();
  }

  Future<void> _loadSession() async {
    _isLoading = true;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    _userRole = prefs.getString('role');
    _userEmail = prefs.getString('email');
    _isLoading = false;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Map<String, String> get authHeader => {
    "Authorization": "Bearer $_token",
  };
}
