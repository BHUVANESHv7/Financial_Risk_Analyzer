import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/insights.dart';
import '../models/risk_result.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

class Page<T> {
  final int total;
  final List<T> items;
  Page(this.total, this.items);
}

/// Thin HTTP client for the backend. The auth service sets [token]
/// and [onUnauthorized] so an expired session logs the user out.
class ApiService {
  static String? token;
  static VoidCallback? onUnauthorized;

  static Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${AppConfig.apiUrl}$path').replace(queryParameters: query);

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static Future<dynamic> _send(Future<http.Response> Function() call,
      {Duration timeout = const Duration(seconds: 20)}) async {
    http.Response res;
    try {
      res = await call().timeout(timeout);
    } on TimeoutException {
      throw ApiException('The server is taking too long to respond. Please try again.');
    } catch (_) {
      throw ApiException('Cannot reach the server. Check that the backend is running.');
    }
    return _decode(res.statusCode, res.body);
  }

  static dynamic _decode(int code, String body) {
    dynamic data;
    try {
      data = body.isEmpty ? null : jsonDecode(body);
    } catch (_) {
      data = null;
    }
    if (code >= 200 && code < 300) return data;
    if (code == 401 && token != null) onUnauthorized?.call();
    throw ApiException(_errorMessage(data, code), code);
  }

  static String _errorMessage(dynamic data, int code) {
    final detail = data is Map ? data['detail'] : null;
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty) {
      // FastAPI validation errors: [{loc: [...], msg: "..."}]
      final first = detail.first;
      if (first is Map) {
        final field = (first['loc'] as List?)?.last?.toString().replaceAll('_', ' ');
        return '${field != null ? '$field: ' : ''}${first['msg']}';
      }
    }
    return 'Request failed ($code)';
  }

  // ── Health / meta ────────────────────────────────────────────
  static Future<bool> checkHealth() async {
    try {
      await _send(() => http.get(_uri('/health')), timeout: const Duration(seconds: 5));
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> meta() async =>
      (await _send(() => http.get(_uri('/meta')))) as Map<String, dynamic>;

  // ── Auth ─────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> login(String email, String password) async =>
      (await _send(() => http.post(_uri('/login'), body: {
                'username': email,
                'password': password,
              }))) as Map<String, dynamic>;

  static Future<void> register(Map<String, dynamic> body) =>
      _send(() => http.post(_uri('/register'), headers: _headers, body: jsonEncode(body)));

  // ── Analysis ─────────────────────────────────────────────────
  /// Upload a document → extracted values + preview report (not saved yet).
  static Future<RiskResult> analyzeDocument(PlatformFile file) async {
    final request = http.MultipartRequest('POST', _uri('/analyze-loan'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    if (file.bytes != null) {
      request.files.add(http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name));
    } else if (!kIsWeb && file.path != null) {
      request.files.add(await http.MultipartFile.fromPath('file', file.path!, filename: file.name));
    } else {
      throw ApiException('Could not read the selected file. Please pick it again.');
    }

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 90));
      final body = await streamed.stream.bytesToString();
      return RiskResult.fromJson(_decode(streamed.statusCode, body) as Map<String, dynamic>);
    } on TimeoutException {
      throw ApiException('Reading the document took too long. Try a smaller or clearer file.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Cannot reach the server. Check that the backend is running.');
    }
  }

  /// Live what-if score. Nothing is saved.
  static Future<RiskResult> recalculate(Map<String, dynamic> features) async =>
      RiskResult.fromJson(await _send(() => http.post(_uri('/recalculate'),
          headers: _headers, body: jsonEncode(features))));

  /// Submit verified values as an application (saved + officers notified live).
  static Future<RiskResult> submitApplication(Map<String, dynamic> features) async =>
      RiskResult.fromJson(await _send(() => http.post(_uri('/applications'),
          headers: _headers, body: jsonEncode(features))));

  // ── Applications ─────────────────────────────────────────────
  static Future<Page<RiskResult>> listApplications({
    String? status,
    String? risk,
    bool? fraud,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final q = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (status != null) 'status': status,
      if (risk != null) 'risk': risk,
      if (fraud != null) 'fraud': '$fraud',
      if (search != null && search.trim().isNotEmpty) 'q': search.trim(),
    };
    final data = await _send(() => http.get(_uri('/applications', q), headers: _headers));
    final items = (data['items'] as List)
        .map((e) => RiskResult.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return Page(data['total'] as int, items);
  }

  static Future<RiskResult> getApplication(int id) async => RiskResult.fromJson(
      await _send(() => http.get(_uri('/applications/$id'), headers: _headers)));

  static Future<RiskResult> review(int id, String status, String? notes) async =>
      RiskResult.fromJson(await _send(() => http.patch(_uri('/applications/$id/review'),
          headers: _headers, body: jsonEncode({'status': status, 'notes': notes}))));

  static Future<RiskResult> withdraw(int id) async => RiskResult.fromJson(
      await _send(() => http.post(_uri('/applications/$id/withdraw'), headers: _headers)));

  /// CSV of applications (officers). Returns (filename, bytes).
  static Future<(String, Uint8List)> exportCsv({String? status, String? risk, bool? fraud}) async {
    final q = <String, String>{
      if (status != null) 'status': status,
      if (risk != null) 'risk': risk,
      if (fraud != null) 'fraud': '$fraud',
    };
    http.Response res;
    try {
      res = await http
          .get(_uri('/applications/export', q.isEmpty ? null : q), headers: _headers)
          .timeout(const Duration(seconds: 60));
    } catch (_) {
      throw ApiException('Cannot reach the server. Check that the backend is running.');
    }
    if (res.statusCode != 200) _decode(res.statusCode, res.body); // throws
    final disposition = res.headers['content-disposition'] ?? '';
    final name = RegExp(r'filename="([^"]+)"').firstMatch(disposition)?.group(1) ?? 'applications.csv';
    return (name, res.bodyBytes);
  }

  static Future<Map<String, dynamic>> stats() async =>
      (await _send(() => http.get(_uri('/stats'), headers: _headers))) as Map<String, dynamic>;

  // ── AI insights ──────────────────────────────────────────────
  /// Path to approval: smallest change that gets automatic approval.
  static Future<Advice> advice(Map<String, dynamic> features) async => Advice.fromJson(
      await _send(() => http.post(_uri('/advice'), headers: _headers, body: jsonEncode(features))));

  /// Hash-chained audit trail of one application.
  static Future<AuditTrail> audit(int id) async => AuditTrail.fromJson(
      await _send(() => http.get(_uri('/applications/$id/audit'), headers: _headers)));

  /// Re-verify the whole audit ledger (officers).
  static Future<Map<String, dynamic>> verifyLedger() async =>
      (await _send(() => http.get(_uri('/audit/verify'), headers: _headers))) as Map<String, dynamic>;

  /// Live data drift vs. training data (officers).
  static Future<ModelHealth> modelHealth() async => ModelHealth.fromJson(
      await _send(() => http.get(_uri('/model/health'), headers: _headers)));
}
