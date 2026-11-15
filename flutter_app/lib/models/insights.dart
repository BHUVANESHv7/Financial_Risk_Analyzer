double _d(dynamic v, [double f = 0]) => v is num ? v.toDouble() : f;

/// One change that would get the loan auto-approved.
class AdviceOption {
  final String key, title, detail, newRiskLevel;
  final double value, newRiskScore, newEmi;
  final int effort;

  AdviceOption({
    required this.key,
    required this.title,
    required this.detail,
    required this.value,
    required this.newRiskScore,
    required this.newRiskLevel,
    required this.newEmi,
    required this.effort,
  });

  factory AdviceOption.fromJson(Map<String, dynamic> j) => AdviceOption(
        key: j['key']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        detail: j['detail']?.toString() ?? '',
        value: _d(j['value']),
        newRiskScore: _d(j['new_risk_score']),
        newRiskLevel: j['new_risk_level']?.toString() ?? 'LOW',
        newEmi: _d(j['new_emi']),
        effort: (j['effort'] as num?)?.toInt() ?? 3,
      );
}

/// "Path to approval" from POST /advice.
class Advice {
  final bool qualifies, fraudBlocked, hasHeadroom;
  final String message, decision;
  final double? maxLoanAmount;
  final List<AdviceOption> options;

  Advice({
    required this.qualifies,
    required this.fraudBlocked,
    this.hasHeadroom = false,
    required this.message,
    required this.decision,
    this.maxLoanAmount,
    this.options = const [],
  });

  factory Advice.fromJson(Map<String, dynamic> j) => Advice(
        qualifies: j['qualifies'] == true,
        fraudBlocked: j['fraud_blocked'] == true,
        hasHeadroom: j['has_headroom'] == true,
        message: j['message']?.toString() ?? '',
        decision: j['decision']?.toString() ?? '',
        maxLoanAmount: (j['max_loan_amount'] as num?)?.toDouble(),
        options: ((j['options'] as List?) ?? const [])
            .map((e) => AdviceOption.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// One entry of the hash-chained audit ledger.
class AuditEvent {
  final int id;
  final String action, hash, prevHash;
  final String? actorEmail, actorRole;
  final DateTime? timestamp;
  final Map<String, dynamic> data;
  final bool verified;

  AuditEvent({
    required this.id,
    required this.action,
    required this.hash,
    required this.prevHash,
    this.actorEmail,
    this.actorRole,
    this.timestamp,
    this.data = const {},
    required this.verified,
  });

  factory AuditEvent.fromJson(Map<String, dynamic> j) => AuditEvent(
        id: (j['id'] as num).toInt(),
        action: j['action']?.toString() ?? '',
        hash: j['hash']?.toString() ?? '',
        prevHash: j['prev_hash']?.toString() ?? '',
        actorEmail: j['actor_email']?.toString(),
        actorRole: j['actor_role']?.toString(),
        timestamp: DateTime.tryParse(j['timestamp']?.toString() ?? '')?.toLocal(),
        data: (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        verified: j['verified'] == true,
      );
}

class AuditTrail {
  final List<AuditEvent> events;
  final bool verified;
  AuditTrail(this.events, this.verified);

  factory AuditTrail.fromJson(Map<String, dynamic> j) => AuditTrail(
        ((j['events'] as List?) ?? const [])
            .map((e) => AuditEvent.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        j['verified'] == true,
      );
}

class FeatureDrift {
  final String feature, label, status;
  final double psi;
  FeatureDrift(this.feature, this.label, this.status, this.psi);

  factory FeatureDrift.fromJson(Map<String, dynamic> j) => FeatureDrift(
        j['feature']?.toString() ?? '',
        j['label']?.toString() ?? '',
        j['status']?.toString() ?? 'stable',
        _d(j['psi']),
      );
}

/// Data drift of live applications vs. training data (GET /model/health).
class ModelHealth {
  final String status, message;
  final int sampleSize;
  final List<FeatureDrift> features;

  ModelHealth({
    required this.status,
    required this.message,
    required this.sampleSize,
    this.features = const [],
  });

  bool get hasData => status != 'insufficient_data';

  factory ModelHealth.fromJson(Map<String, dynamic> j) => ModelHealth(
        status: j['status']?.toString() ?? 'insufficient_data',
        message: j['message']?.toString() ?? '',
        sampleSize: (j['sample_size'] as num?)?.toInt() ?? 0,
        features: ((j['features'] as List?) ?? const [])
            .map((e) => FeatureDrift.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}
