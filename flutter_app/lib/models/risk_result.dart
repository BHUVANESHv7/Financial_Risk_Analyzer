import 'package:flutter/material.dart';

class RiskResult {
  final String applicantName;
  final String riskLevel;      // LOW / MEDIUM / HIGH
  final String decision;       // APPROVE / MANUAL REVIEW / REJECT
  final double confidence;     // 0.0 to 1.0
  final double monthlyIncome;
  final double loanAmount;
  final double existingEmis;
  final bool fraudFlag;
  final bool compliant;
  final String reportSummary;
  final Map<String, dynamic> features;
  final Map<String, dynamic>? biasReport;
  final String? fileName;

  RiskResult({
    required this.applicantName,
    required this.riskLevel, 
    required this.decision,
    required this.confidence,
    required this.monthlyIncome,
    required this.loanAmount,
    required this.existingEmis,
    required this.fraudFlag,
    required this.compliant,
    required this.reportSummary,
    this.features = const {},
    this.biasReport,
    this.fileName,
  });

  factory RiskResult.fromJson(Map<String, dynamic> json) {
    return RiskResult(
      applicantName: json['applicant_name'] ?? 'Unknown',
      riskLevel:     json['risk_level']     ?? 'UNKNOWN',
      decision:      json['decision']       ?? 'UNKNOWN',
      confidence:    _parseNum(json['confidence']),
      monthlyIncome: _parseNum(json['monthly_income']),
      loanAmount:    _parseNum(json['loan_amount']),
      existingEmis:  _parseNum(json['existing_emis']),
      fraudFlag:     json['fraud_flag']      ?? false,
      compliant:     json['compliant']        ?? true,
      reportSummary: json['report_summary']  ?? 'No summary available.',
      features:      json['features']        ?? {},
      biasReport:    json['bias_report'],
    );
  }

  static double _parseNum(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    if (v is String) {
      return double.tryParse(v.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    }
    return 0.0;
  }

  RiskResult copyWithFileName(String? name) {
    return RiskResult(
      applicantName: applicantName,
      riskLevel: riskLevel,
      decision: decision,
      confidence: confidence,
      monthlyIncome: monthlyIncome,
      loanAmount: loanAmount,
      existingEmis: existingEmis,
      fraudFlag: fraudFlag,
      compliant: compliant,
      reportSummary: reportSummary,
      features: features,
      biasReport: biasReport,
      fileName: name,
    );
  }

  // Colour for the risk level badge
  static Map<String, dynamic> riskMeta(String level) {
    switch (level.toUpperCase()) {
      case 'LOW':
        return {
          'color': const Color(0xFF03543F),
          'bg':    const Color(0xFFDEF7EC),
          'icon':  '✓',
          'label': 'Low Risk',
        };
      case 'HIGH':
        return {
          'color': const Color(0xFF9B1C1C),
          'bg':    const Color(0xFFFDE8E8),
          'icon':  '✗',
          'label': 'High Risk',
        };
      default:
        return {
          'color': const Color(0xFF92400E),
          'bg':    const Color(0xFFFEF3C7),
          'icon':  '!',
          'label': 'Medium Risk',
        };
    }
  }

  static Map<String, dynamic> decisionMeta(String decision) {
    switch (decision.toUpperCase()) {
      case 'APPROVE':
        return {
          'color': Colors.white, 
          'bg': const Color(0xFF0E9F6E),
          'icon': '✓',
        };
      case 'REJECT':
        return {
          'color': const Color(0xFF9B1C1C), 
          'bg': const Color(0xFFFDE8E8),
          'icon': '✗',
        };
      default:
        return {
          'color': const Color(0xFF92400E), 
          'bg': const Color(0xFFFEF3C7),
          'icon': '!',
        };
    }
  }
}
