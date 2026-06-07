import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'home_screen.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import '../models/risk_result.dart';
import 'result_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  List<Map<String, dynamic>> _applications = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchApplications();
  }

  Future<void> _fetchApplications() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    try {
      final data = await ApiService.getHistory(auth.token!);
      setState(() {
        _applications = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeService>(context);
    final isDark = theme.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Review Panel'),
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _fetchApplications();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Provider.of<AuthService>(context, listen: false).logout();
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
              : _applications.isEmpty
                  ? const Center(child: Text('No applications to review.'))
                  : Column(
                      children: [
                        _buildStatsHeader(),
                        Expanded(child: _buildApplicationsList(isDark)),
                      ],
                    ),
    );
  }

  Widget _buildStatsHeader() {
    final manualCount = _applications.where((a) => a['decision'] == 'MANUAL REVIEW').length;
    final fraudCount = _applications.where((a) => a['fraud_flag'] == true).length;

    return Container(
      padding: const EdgeInsets.all(20),
      color: Provider.of<ThemeService>(context).isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatCard(label: 'Total', value: _applications.length.toString(), color: Colors.blue),
          _StatCard(label: 'Pending', value: manualCount.toString(), color: Colors.orange),
          _StatCard(label: 'Fraud Alert', value: fraudCount.toString(), color: Colors.red),
        ],
      ),
    );
  }

  Widget _buildApplicationsList(bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _applications.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final doc = _applications[index];
        final name = doc['applicant_name'] ?? 'Anonymous';
        final risk = doc['risk_level'] ?? 'N/A';
        final decision = doc['decision'] ?? 'PENDING';
        final isFraud = doc['fraud_flag'] ?? false;

        return Card(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          child: InkWell(
            onTap: () {
              final result = RiskResult.fromJson(doc);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isFraud ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                child: Icon(
                  isFraud ? Icons.warning_amber_rounded : Icons.person_outline,
                  color: isFraud ? Colors.red : Colors.green,
                ),
              ),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('ID: #${doc['id']} • ${doc['timestamp'].substring(0, 10)}'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusBadge(label: risk, color: _getRiskColor(risk)),
                  const SizedBox(height: 4),
                  Text(
                    decision,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _getDecisionColor(decision),
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

  Color _getRiskColor(String risk) {
    if (risk == 'LOW') return Colors.green;
    if (risk == 'HIGH') return Colors.red;
    return Colors.orange;
  }

  Color _getDecisionColor(String decision) {
    if (decision == 'APPROVE') return Colors.green;
    if (decision == 'REJECT') return Colors.red;
    return Colors.orange;
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
