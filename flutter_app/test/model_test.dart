import 'package:flutter_test/flutter_test.dart';
import 'package:loan_app/models/risk_result.dart';
import 'package:loan_app/utils/format.dart';

void main() {
  group('RiskResult.fromJson', () {
    test('parses a full saved application', () {
      final r = RiskResult.fromJson({
        'id': 7,
        'applicant_name': 'Ravi Kumar',
        'risk_level': 'LOW',
        'risk_score': 12.5,
        'decision': 'APPROVE',
        'status': 'APPROVED',
        'confidence': 0.93,
        'monthly_income': 62000,
        'loan_amount': '8,00,000', // strings with separators are tolerated
        'existing_emis': 4500,
        'credit_score': 742,
        'loan_category': 'Vehicle',
        'tenure_months': 60,
        'fraud_flag': false,
        'compliant': true,
        'ratios': {'new_emi': 17195.0, 'dti': 0.35},
        'factors': [
          {'label': 'Credit score', 'value': '742', 'impact': 'positive', 'detail': 'Good'}
        ],
        'compliance_checks': [
          {'code': 'R1', 'rule': 'Minimum income', 'passed': true}
        ],
        'timestamp': '2026-11-10T06:30:00+00:00',
        'reviewed_at': null,
      });

      expect(r.id, 7);
      expect(r.isSaved, isTrue);
      expect(r.isReviewed, isFalse);
      expect(r.loanAmount, 800000);
      expect(r.newEmi, 17195.0);
      expect(r.dti, 0.35);
      expect(r.factors.single.impact, 'positive');
      expect(r.checks.single.passed, isTrue);
      expect(r.timestamp!.isUtc, isFalse); // converted to local time
    });

    test('derives status from the AI decision for previews', () {
      expect(RiskResult.fromJson({'decision': 'REJECT'}).status, 'REJECTED');
      expect(RiskResult.fromJson({'decision': 'APPROVE'}).status, 'APPROVED');
      expect(RiskResult.fromJson({'decision': 'MANUAL REVIEW'}).status, 'PENDING');
    });

    test('falls back to features for list items without top-level values', () {
      final r = RiskResult.fromJson({
        'features': {'monthly_income': 40000, 'loan_category': 'Education', 'source_file': 'slip.pdf'},
      });
      expect(r.monthlyIncome, 40000);
      expect(r.loanCategory, 'Education');
      expect(r.fileName, 'slip.pdf');
      expect(r.isSaved, isFalse);
    });
  });

  group('format', () {
    test('uses Indian digit grouping', () {
      expect(inr(500000), '₹5,00,000');
      expect(inr(45000), '₹45,000');
    });

    test('compacts large amounts only', () {
      expect(inrCompact(45000), '₹45,000');
      expect(inrCompact(900000), contains('L'));
    });

    test('percent and relative time', () {
      expect(pct(0.275), '28%');
      expect(relativeTime(DateTime.now()), 'just now');
      expect(relativeTime(DateTime.now().subtract(const Duration(hours: 3))), '3h ago');
      expect(relativeTime(null), '');
    });
  });
}
