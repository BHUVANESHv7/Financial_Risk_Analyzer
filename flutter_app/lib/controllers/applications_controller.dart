import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/risk_result.dart';
import '../services/api_service.dart';
import '../services/realtime_service.dart';

/// Loads a filtered list of applications and keeps it in sync with live
/// WebSocket events, so every list in the app updates without refreshing.
class ApplicationsController extends ChangeNotifier {
  final RealtimeService realtime;
  final int pageSize;
  final bool withStats;

  ApplicationsController(this.realtime, {this.pageSize = 30, this.withStats = false}) {
    _sub = realtime.events.listen(_onEvent);
    // After a reconnect, reload to catch anything missed while offline.
    _wasLive = realtime.isLive;
    realtime.addListener(_onRealtimeChanged);
  }

  late final StreamSubscription<LiveEvent> _sub;
  late bool _wasLive;
  Timer? _statsDebounce;

  List<RiskResult> items = [];
  int total = 0;
  bool loading = false;
  bool loadingMore = false;
  String? error;
  Map<String, dynamic>? stats;
  final Set<int> highlighted = {};

  // Filters
  String? status;
  String? risk;
  bool? fraud;
  String search = '';

  bool get hasMore => items.length < total;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        ApiService.listApplications(
            status: status, risk: risk, fraud: fraud, search: search, limit: pageSize),
        if (withStats) ApiService.stats(),
      ]);
      final page = results[0] as Page<RiskResult>;
      items = page.items;
      total = page.total;
      if (withStats) stats = results[1] as Map<String, dynamic>;
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (loadingMore || !hasMore) return;
    loadingMore = true;
    notifyListeners();
    try {
      final page = await ApiService.listApplications(
          status: status, risk: risk, fraud: fraud, search: search,
          limit: pageSize, offset: items.length);
      final known = items.map((e) => e.id).toSet();
      items.addAll(page.items.where((e) => !known.contains(e.id)));
      total = page.total;
    } catch (_) {
      // keep what we have; user can scroll again
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  void setFilter({String? status, String? risk, bool? fraud, bool clear = false}) {
    if (clear) {
      this.status = null;
      this.risk = null;
      this.fraud = null;
    }
    this.status = status ?? this.status;
    this.risk = risk ?? this.risk;
    this.fraud = fraud ?? this.fraud;
    load();
  }

  Future<void> refreshStats() async {
    if (!withStats) return;
    try {
      stats = await ApiService.stats();
      notifyListeners();
    } catch (_) {}
  }

  bool _matches(RiskResult a) {
    if (status != null && a.status != status) return false;
    if (risk != null && a.riskLevel != risk) return false;
    if (fraud != null && a.fraudFlag != fraud) return false;
    if (search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      final hay = '${a.applicantName} ${a.applicantEmail ?? ''}'.toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }

  void _onEvent(LiveEvent e) {
    if (e.type == 'stats.changed') {
      _statsDebounce?.cancel();
      _statsDebounce = Timer(const Duration(milliseconds: 400), refreshStats);
      return;
    }
    if (!e.isApplication) return;
    final app = RiskResult.fromJson(e.data);
    final idx = items.indexWhere((x) => x.id == app.id);

    if (e.type == 'application.created') {
      if (idx >= 0 || !_matches(app)) return;
      items.insert(0, app);
      total++;
      _flash(app.id!);
    } else if (e.type == 'application.updated') {
      if (idx >= 0) {
        if (_matches(app)) {
          items[idx] = app;
          _flash(app.id!);
        } else {
          items.removeAt(idx);
          total--;
        }
      } else if (_matches(app)) {
        // e.g. moved into the current filter by a review
        items.insert(0, app);
        items.sort((a, b) => (b.timestamp ?? DateTime(0)).compareTo(a.timestamp ?? DateTime(0)));
        total++;
        _flash(app.id!);
      }
    }
    notifyListeners();
  }

  void _flash(int id) {
    highlighted.add(id);
    Timer(const Duration(seconds: 4), () {
      if (highlighted.remove(id)) notifyListeners();
    });
  }

  void _onRealtimeChanged() {
    if (realtime.isLive && !_wasLive && items.isNotEmpty) load();
    _wasLive = realtime.isLive;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _sub.cancel();
    _statsDebounce?.cancel();
    realtime.removeListener(_onRealtimeChanged);
    super.dispose();
  }
}
