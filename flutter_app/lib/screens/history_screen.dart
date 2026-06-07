import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../models/risk_result.dart';
import 'result_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    try {
      final data = await ApiService.getHistory(auth.token!);
      if (mounted) {
        setState(() {
          _history = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Color _riskColor(String level) {
    switch (level.toUpperCase()) {
      case 'LOW':    return const Color(0xFF057A55);
      case 'HIGH':   return const Color(0xFF9B1C1C);
      default:       return const Color(0xFF92400E);
    }
  }

  Color _riskBg(String level) {
    switch (level.toUpperCase()) {
      case 'LOW':    return const Color(0xFFDEF7EC);
      case 'HIGH':   return const Color(0xFFFDE8E8);
      default:       return const Color(0xFFFEF3C7);
    }
  }

  String _formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString);
      return DateFormat('dd MMM yyyy, hh:mm a').format(date);
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<ThemeService>(context).isDarkMode;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Analysis History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _fetchHistory();
            },
          ),
        ],
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text('Error: $_error', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchHistory,
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_history.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 60, color: Color(0xFF4B5563)),
            SizedBox(height: 12),
            Text('No analyses yet',
                style: TextStyle(color: Color(0xFF374151), fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final h = _history[i];
        final name = h['applicant_name'] ?? 'Unknown';
        final risk = h['risk_level'] ?? 'MEDIUM';
        final dateStr = h['timestamp'] ?? '';
        final decision = h['decision'] ?? 'MANUAL REVIEW';

        return Card(
          elevation: 0,
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200]!),
          ),
          child: InkWell(
            onTap: () {
              final result = RiskResult.fromJson(h);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              leading: CircleAvatar(
                backgroundColor: _riskBg(risk),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                      color: _riskColor(risk),
                      fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  )),
              subtitle: Text(_formatDate(dateStr),
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : const Color(0xFF374151), 
                    fontSize: 12
                  )),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: _riskBg(risk),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(risk,
                        style: TextStyle(
                            color: _riskColor(risk),
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    decision,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: decision == 'APPROVE' ? Colors.green : (decision == 'REJECT' ? Colors.red : Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
