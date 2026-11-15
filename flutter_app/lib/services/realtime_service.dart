import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import 'api_service.dart';

enum LiveStatus { offline, connecting, live }

class LiveEvent {
  final String type;
  final Map<String, dynamic> data;
  LiveEvent(this.type, this.data);

  int? get applicationId => data['id'] as int?;
  bool get isApplication => type.startsWith('application.');
}

/// Keeps one WebSocket open to the backend while the user is signed in.
/// Reconnects automatically with exponential backoff and exposes a
/// broadcast [events] stream that screens subscribe to.
class RealtimeService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat, _retry;
  String? _token;
  int _attempt = 0;

  LiveStatus _status = LiveStatus.offline;
  int officersOnline = 0;
  int applicantsOnline = 0;

  final _events = StreamController<LiveEvent>.broadcast();
  Stream<LiveEvent> get events => _events.stream;
  LiveStatus get status => _status;
  bool get isLive => _status == LiveStatus.live;

  /// Called whenever auth changes (see main.dart).
  void updateToken(String? token) {
    if (token == _token) return;
    _token = token;
    _close();
    if (token != null) _connect();
  }

  /// Lets tests simulate a server event without a socket.
  @visibleForTesting
  void debugEmit(LiveEvent event) => _events.add(event);

  void reconnectNow() {
    if (_token == null) return;
    _attempt = 0;
    _close();
    _connect();
  }

  Future<void> _connect() async {
    final token = _token;
    if (token == null) return;
    _setStatus(LiveStatus.connecting);
    final channel = WebSocketChannel.connect(AppConfig.wsUri);
    _channel = channel;
    try {
      await channel.ready;
      if (_channel != channel) return; // superseded while connecting
      _sub = channel.stream.listen(_onMessage, onError: (_) => _onDropped(), onDone: () {
        if (channel.closeCode == 4401) {
          // Token rejected (expired session): stop retrying and sign out.
          _cleanup();
          _setStatus(LiveStatus.offline);
          ApiService.onUnauthorized?.call();
        } else {
          _onDropped();
        }
      });
      channel.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _channel?.sink.add('ping');
        } catch (_) {}
      });
    } catch (_) {
      if (_channel == channel) _onDropped();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String? ?? '';
      final data = (msg['data'] as Map?)?.cast<String, dynamic>() ?? {};
      if (type == 'hello') {
        _attempt = 0; // authenticated — now we're live
        _setStatus(LiveStatus.live);
      }
      if (type == 'presence' || type == 'hello') {
        officersOnline = data['officers_online'] as int? ?? officersOnline;
        applicantsOnline = data['applicants_online'] as int? ?? applicantsOnline;
        notifyListeners();
      }
      if (type != 'pong') _events.add(LiveEvent(type, data));
    } catch (_) {}
  }

  void _onDropped() {
    _cleanup();
    if (_token == null) {
      _setStatus(LiveStatus.offline);
      return;
    }
    _setStatus(LiveStatus.offline);
    final delay = Duration(seconds: min(30, pow(2, _attempt).toInt()));
    _attempt++;
    _retry = Timer(delay, _connect);
  }

  void _cleanup() {
    _heartbeat?.cancel();
    _sub?.cancel();
    _heartbeat = null;
    _sub = null;
    _channel = null;
  }

  void _close() {
    _retry?.cancel();
    final ch = _channel;
    _cleanup();
    try {
      ch?.sink.close();
    } catch (_) {}
    _setStatus(LiveStatus.offline);
  }

  void _setStatus(LiveStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _token = null;
    _close();
    _events.close();
    super.dispose();
  }
}
