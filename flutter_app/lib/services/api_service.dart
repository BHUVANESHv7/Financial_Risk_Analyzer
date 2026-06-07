import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'; // Added to allow checking for kIsWeb
import '../models/risk_result.dart';

class ApiService {
  // ── Change this to your deployed Render/AWS URL in production ──
  static String get _baseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8000'; 
    }
    return 'http://10.0.2.2:8000'; // For Android Emulator
  }
  // For iOS simulator use: http://localhost:8000
  // For real device on same WiFi: http://YOUR_LAPTOP_IP:8000
  // For production: https://your-app.onrender.com

  // ── Analyse a loan document ──────────────────────────────────
  static Future<RiskResult> analyzeLoan(PlatformFile file, String token) async {
    final uri = Uri.parse('$_baseUrl/analyze-loan');

    final request = http.MultipartRequest('POST', uri);
    
    request.headers.addAll({
      "Authorization": "Bearer $token",
    });

    // Attach the file
    if (kIsWeb) {
      if (file.bytes == null) {
        throw Exception('File data is missing. Please try picking the file again.');
      }
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          file.bytes!,
          filename: file.name,
        ),
      );
    } else {
      if (file.path == null) {
        throw Exception('File path is missing. Please try picking the file again.');
      }
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path!,
          filename: file.name,
        ),
      );
    }

    // Set timeout
    final response = await request.send().timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception('Server took too long. Please try again.'),
    );

    final body = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return RiskResult.fromJson(json).copyWithFileName(file.name);
    } else {
      final err = jsonDecode(body);
      throw Exception(err['detail'] ?? 'Something went wrong on the server.');
    }
  }

  // ── Recalculate risk based on modified features ───────────────
  static Future<RiskResult> recalculate(Map<String, dynamic> features, {String? fileName}) async {
    final uri = Uri.parse('$_baseUrl/recalculate');
    
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(features),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return RiskResult.fromJson(json).copyWithFileName(fileName);
    } else {
      final err = jsonDecode(response.body);
      throw Exception(err['detail'] ?? 'Failed to recalculate risk.');
    }
  }

  // ── Health check — ping backend ──────────────────────────────
  static Future<bool> checkHealth() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Fetch history from backend ────────────────────────────────
  static Future<List<Map<String, dynamic>>> getHistory(String token) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/history'),
      headers: {
        "Authorization": "Bearer $token",
      },
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load history');
    }
  }
}
