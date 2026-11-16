import 'package:flutter/foundation.dart';

/// Where the backend lives.
///
/// Web: when the app is served by the backend itself (Docker / Render deploy)
/// it talks to the same origin automatically. During development
/// (`flutter run -d chrome` or a static file server on another port) it uses
/// http://127.0.0.1:8000.
///
/// Override at build/run time:
///   flutter run --dart-define=API_URL=http://192.168.1.10:8000
///   flutter build apk --dart-define=API_URL=https://your-app.onrender.com
///   flutter build web --dart-define=SAME_ORIGIN=true   (always use the page's origin)
class AppConfig {
  static const String _override = String.fromEnvironment('API_URL');
  static const bool _sameOrigin = bool.fromEnvironment('SAME_ORIGIN');
  static const String _devApi = 'http://127.0.0.1:8000';

  static String get apiUrl {
    if (_override.isNotEmpty) return _trim(_override);
    if (kIsWeb) return webApiUrl(Uri.base, sameOrigin: _sameOrigin);
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000'; // Android emulator → host machine
    }
    return _devApi;
  }

  /// API base for a web page loaded from [page].
  @visibleForTesting
  static String webApiUrl(Uri page, {bool sameOrigin = false}) {
    if (sameOrigin || !page.hasAuthority) {
      return page.hasAuthority ? page.origin : _devApi;
    }
    final local = page.host == 'localhost' || page.host == '127.0.0.1';
    // A local dev server on another port → the API runs separately on :8000.
    if (local && page.port != 8000) return _devApi;
    return page.origin;
  }

  static String _trim(String url) => url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// WebSocket endpoint derived from the API URL (http→ws, https→wss).
  /// The token is sent in the first message, not the URL.
  static Uri get wsUri {
    final base = Uri.parse(apiUrl);
    return base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/ws');
  }
}
