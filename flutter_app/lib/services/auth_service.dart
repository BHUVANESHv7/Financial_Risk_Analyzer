import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class AuthService extends ChangeNotifier {
  String? _token, _role, _email, _fullName;
  bool _ready = false;
  bool _busy = false;

  bool get ready => _ready;
  bool get isAuthenticated => _token != null;
  bool get isAdmin => _role == 'ADMIN';
  bool get isLoading => _busy;
  String? get token => _token;
  String? get userEmail => _email;
  String get displayName =>
      (_fullName?.isNotEmpty ?? false) ? _fullName! : (_email?.split('@').first ?? 'User');

  AuthService() {
    ApiService.onUnauthorized = () => logout();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    _role = prefs.getString('role');
    _email = prefs.getString('email');
    _fullName = prefs.getString('full_name');
    ApiService.token = _token;
    _ready = true;
    notifyListeners();
  }

  Future<void> login({required String email, required String password}) async {
    _setBusy(true);
    try {
      final data = await ApiService.login(email.trim(), password);
      _token = data['access_token'];
      _role = data['role'];
      _email = data['email'];
      _fullName = data['full_name'];
      ApiService.token = _token;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', _token!);
      await prefs.setString('role', _role ?? 'APPLICANT');
      await prefs.setString('email', _email ?? '');
      await prefs.setString('full_name', _fullName ?? '');
    } finally {
      _setBusy(false);
    }
  }

  Future<void> register({
    required String email,
    required String password,
    String? fullName,
    String role = 'APPLICANT',
    String? inviteCode,
  }) async {
    _setBusy(true);
    try {
      await ApiService.register({
        'email': email.trim(),
        'password': password,
        'full_name': fullName,
        'role': role,
        if (inviteCode != null && inviteCode.isNotEmpty) 'invite_code': inviteCode,
      });
    } finally {
      _setBusy(false);
    }
  }

  Future<void> logout() async {
    if (_token == null) return;
    _token = _role = _email = _fullName = null;
    ApiService.token = null;
    final prefs = await SharedPreferences.getInstance();
    for (final k in ['token', 'role', 'email', 'full_name']) {
      await prefs.remove(k); // keep other prefs such as the theme
    }
    notifyListeners();
  }

  void _setBusy(bool v) {
    _busy = v;
    notifyListeners();
  }
}
