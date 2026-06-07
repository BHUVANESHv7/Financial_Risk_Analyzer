import 'package:flutter/material.dart';
import '../models/risk_result.dart';
import '../widgets/risk_badge.dart';
import 'home_screen.dart';

class ResultScreen extends StatelessWidget {
  final RiskResult result;
  const ResultScreen({super.key, required this.result});

  String _currency(double v) =>
      '₹${v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')}';


  @override
  Widget build(BuildContext context) {
    final rMeta = RiskResult.riskMeta(result.riskLevel);
    final dMeta = RiskResult.decisionMeta(result.decision);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Risk Assessment Result'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Risk Level Badge ─────────────────────────────────────
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  color: rMeta['bg'] as Color,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  rMeta['label'] as String,
                  style: TextStyle(
                    color: rMeta['color'] as Color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Decision banner ───────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: dMeta['bg'] as Color,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: (dMeta['bg'] as Color).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    dMeta['icon'] as String,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: dMeta['color'] as Color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    result.decision == 'APPROVE' ? 'Approved' : result.decision,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: dMeta['color'] as Color,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const SizedBox(height: 20),

            // ── Details card ──────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Applicant Details',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const Divider(height: 20),
                    InfoRow(label: 'Name',           value: result.applicantName),
                    InfoRow(label: 'Monthly income', value: _currency(result.monthlyIncome)),
                    InfoRow(label: 'Loan amount',    value: _currency(result.loanAmount)),
                    InfoRow(label: 'Existing EMIs',  value: _currency(result.existingEmis)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Compliance & fraud card ───────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Compliance & Fraud Check',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const Divider(height: 20),
                    _CheckRow(
                        label: 'Regulatory compliant',
                        passed: result.compliant),
                    _CheckRow(
                        label: 'No fraud detected',
                        passed: !result.fraudFlag),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── AI summary card ───────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.summarize_outlined,
                            color: Color(0xFF1A56DB), size: 18),
                        SizedBox(width: 6),
                        Text('AI Report Summary',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(result.reportSummary,
                        style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF111827),
                            height: 1.6)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Action buttons ────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                      (r) => false,
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('New Analysis'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green),
                              SizedBox(width: 8),
                              Text('Report Saved'),
                            ],
                          ),
                          content: const Text(
                              'This analysis has been automatically saved to your cloud history and can be viewed anytime in the History tab.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.bookmark_added_outlined),
                    label: const Text('Save Report'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────


class _CheckRow extends StatelessWidget {
  final String label;
  final bool passed;
  const _CheckRow({required this.label, required this.passed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: passed
                ? const Color(0xFFDEF7EC)
                : const Color(0xFFFDE8E8),
            child: Icon(
              passed ? Icons.check : Icons.close,
              size: 14,
              color: passed
                  ? const Color(0xFF057A55)
                  : const Color(0xFF9B1C1C),
            ),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827))),
        ],
      ),
    );
  }
}
