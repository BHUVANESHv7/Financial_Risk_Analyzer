import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

double _num(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  if (v is String) {
    return double.tryParse(v.replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? fallback;
  }
  return fallback;
}

List<String> _strings(dynamic v) =>
    v is List ? v.map((e) => e.toString()).toList() : const [];

class RiskFactor {
  final String label, value, impact, detail;
  RiskFactor(this.label, this.value, this.impact, this.detail);

  factory RiskFactor.fromJson(Map<String, dynamic> j) => RiskFactor(
        j['label']?.toString() ?? '',
        j['value']?.toString() ?? '',
        j['impact']?.toString() ?? 'neutral',
        j['detail']?.toString() ?? '',
      );
}

class ComplianceCheck {
  final String code, rule;
  final bool passed;
  ComplianceCheck(this.code, this.rule, this.passed);

  factory ComplianceCheck.fromJson(Map<String, dynamic> j) =>
      ComplianceCheck(j['code'] ?? '', j['rule'] ?? '', j['passed'] == true);
}

/// A risk report — either a live preview or a saved application.
class RiskResult {
  final int? id;
  final String applicantName;
  final String? applicantEmail;
  final String riskLevel; // LOW / MEDIUM / HIGH
  final double riskScore; // 0..100
  final String decision; // APPROVE / MANUAL REVIEW / REJECT (AI recommendation)
  final String status; // PENDING / APPROVED / REJECTED (final, after review)
  final double confidence;
  final double monthlyIncome, loanAmount, existingEmis, creditScore;
  final String? loanCategory;
  final int? tenureMonths;
  final bool fraudFlag, compliant;
  final List<String> fraudReasons, fraudWarnings, violations;
  final List<ComplianceCheck> checks;
  final List<RiskFactor> factors;
  final Map<String, dynamic> ratios;
  final Map<String, dynamic> features;
  final Map<String, dynamic>? biasReport;
  final String reportSummary;
  final DateTime? timestamp, reviewedAt;
  final String? reviewerNotes, reviewerEmail;
  final String? fileName;

  RiskResult({
    this.id,
    required this.applicantName,
    this.applicantEmail,
    required this.riskLevel,
    required this.riskScore,
    required this.decision,
    required this.status,
    required this.confidence,
    required this.monthlyIncome,
    required this.loanAmount,
    required this.existingEmis,
    required this.creditScore,
    this.loanCategory,
    this.tenureMonths,
    required this.fraudFlag,
    required this.compliant,
    this.fraudReasons = const [],
    this.fraudWarnings = const [],
    this.violations = const [],
    this.checks = const [],
    this.factors = const [],
    this.ratios = const {},
    this.features = const {},
    this.biasReport,
    this.reportSummary = '',
    this.timestamp,
    this.reviewedAt,
    this.reviewerNotes,
    this.reviewerEmail,
    this.fileName,
  });

  bool get isSaved => id != null;
  bool get isReviewed => reviewedAt != null;
  double get newEmi => _num(ratios['new_emi']);
  double get dti => _num(ratios['dti']);

  factory RiskResult.fromJson(Map<String, dynamic> j) {
    final features = (j['features'] as Map?)?.cast<String, dynamic>() ?? {};
    final decision = j['decision']?.toString() ?? 'MANUAL REVIEW';
    return RiskResult(
      id: j['id'] as int?,
      applicantName: j['applicant_name']?.toString() ?? 'Unknown',
      applicantEmail: j['applicant_email']?.toString(),
      riskLevel: j['risk_level']?.toString() ?? 'MEDIUM',
      riskScore: _num(j['risk_score'], 50),
      decision: decision,
      status: j['status']?.toString() ?? _statusFor(decision),
      confidence: _num(j['confidence']),
      monthlyIncome: _num(j['monthly_income'] ?? features['monthly_income']),
      loanAmount: _num(j['loan_amount'] ?? features['loan_amount']),
      existingEmis: _num(j['existing_emis'] ?? features['existing_emis']),
      creditScore: _num(j['credit_score'] ?? features['credit_score']),
      loanCategory: (j['loan_category'] ?? features['loan_category'])?.toString(),
      tenureMonths: _num(j['tenure_months'] ?? features['tenure_months']).toInt(),
      fraudFlag: j['fraud_flag'] == true,
      compliant: j['compliant'] != false,
      fraudReasons: _strings(j['fraud_reasons']),
      fraudWarnings: _strings(j['fraud_warnings']),
      violations: _strings(j['violations']),
      checks: (j['compliance_checks'] as List? ?? [])
          .map((e) => ComplianceCheck.fromJson((e as Map).cast()))
          .toList(),
      factors: (j['factors'] as List? ?? [])
          .map((e) => RiskFactor.fromJson((e as Map).cast()))
          .toList(),
      ratios: (j['ratios'] as Map?)?.cast<String, dynamic>() ?? {},
      features: features,
      biasReport: (j['bias_report'] as Map?)?.cast<String, dynamic>(),
      reportSummary: j['report_summary']?.toString() ?? '',
      timestamp: DateTime.tryParse(j['timestamp']?.toString() ?? '')?.toLocal(),
      reviewedAt: DateTime.tryParse(j['reviewed_at']?.toString() ?? '')?.toLocal(),
      reviewerNotes: j['reviewer_notes']?.toString(),
      reviewerEmail: j['reviewer_email']?.toString(),
      fileName: features['source_file']?.toString(),
    );
  }

  static String _statusFor(String decision) => switch (decision) {
        'APPROVE' => 'APPROVED',
        'REJECT' => 'REJECTED',
        _ => 'PENDING',
      };
}

/// Visual metadata for risk levels / decisions / statuses.
class Tone {
  final Color fg, bg;
  final IconData icon;
  final String label;
  const Tone(this.fg, this.bg, this.icon, this.label);

  static Tone risk(BuildContext context, String level) {
    final p = context.palette;
    return switch (level.toUpperCase()) {
      'LOW' => Tone(p.success, p.successBg, Icons.shield_outlined, 'Low risk'),
      'HIGH' => Tone(p.danger, p.dangerBg, Icons.warning_amber_rounded, 'High risk'),
      _ => Tone(p.warning, p.warningBg, Icons.error_outline, 'Medium risk'),
    };
  }

  static Tone status(BuildContext context, String status) {
    final p = context.palette;
    return switch (status.toUpperCase()) {
      'APPROVED' || 'APPROVE' => Tone(p.success, p.successBg, Icons.check_circle_rounded, 'Approved'),
      'REJECTED' || 'REJECT' => Tone(p.danger, p.dangerBg, Icons.cancel_rounded, 'Rejected'),
      _ => Tone(p.warning, p.warningBg, Icons.hourglass_top_rounded, 'Pending review'),
    };
  }

  static Tone decision(BuildContext context, String decision) {
    final t = status(context, decision);
    return decision.toUpperCase() == 'MANUAL REVIEW'
        ? Tone(t.fg, t.bg, Icons.person_search_rounded, 'Manual review')
        : t;
  }
}
