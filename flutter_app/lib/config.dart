import 'package:flutter/foundation.dart';

/// Where the backend lives.
///
/// Override at build/run time:
///   flutter run --dart-define=API_URL=http://192.168.1.10:8000
///   flutter build web --dart-define=API_URL=https://your-api.onrender.com
class AppConfig {
  static const String _override = String.fromEnvironment('API_URL');

  static String get apiUrl {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) return 'http://127.0.0.1:8000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000'; // Android emulator → host machine
    }
    return 'http://127.0.0.1:8000';
  }

  /// WebSocket endpoint derived from the API URL (http→ws, https→wss).
  /// The token is sent in the first message, not the URL.
  static Uri get wsUri {
    final base = Uri.parse(apiUrl);
    return base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/ws');
  }
}
