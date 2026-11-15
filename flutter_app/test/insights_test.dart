import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_app/models/insights.dart';
import 'package:loan_app/theme/app_theme.dart';
import 'package:loan_app/widgets/insights_widgets.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

final _pending = Advice.fromJson({
  'decision': 'MANUAL REVIEW',
  'qualifies': false,
  'fraud_blocked': false,
  'message': 'Any one of these 2 changes would get this loan approved automatically.',
  'options': [
    {
      'key': 'tenure_months', 'value': 84, 'title': 'Repay over 84 months',
      'detail': 'Lower EMI.', 'effort': 1, 'new_risk_score': 18.2,
      'new_risk_level': 'LOW', 'new_emi': 8400.0,
    },
    {
      'key': 'loan_amount', 'value': 310000, 'title': 'Borrow ₹3,10,000',
      'detail': 'Less than requested.', 'effort': 2, 'new_risk_score': 22.0,
      'new_risk_level': 'LOW', 'new_emi': 6600.0,
    },
  ],
});

void main() {
  test('advice, audit and health parse from the API', () {
    expect(_pending.options.length, 2);
    expect(_pending.options.first.value, 84);

    final trail = AuditTrail.fromJson({
      'verified': true,
      'events': [
        {
          'id': 1, 'action': 'CREATED', 'hash': 'a' * 64, 'prev_hash': '0' * 64,
          'actor_email': 'a@b.com', 'timestamp': '2026-01-01T10:00:00+00:00',
          'data': {'status': 'PENDING'}, 'verified': true,
        },
      ],
    });
    expect(trail.verified, isTrue);
    expect(trail.events.single.timestamp, isNotNull);

    final h = ModelHealth.fromJson({'status': 'insufficient_data', 'sample_size': 3, 'message': 'x'});
    expect(h.hasData, isFalse);
  });

  testWidgets('approval path lists options and applies the chosen one', (tester) async {
    AdviceOption? applied;
    await tester.pumpWidget(wrap(ApprovalPathCard(advice: _pending, onApply: (o) => applied = o)));
    expect(find.text('Repay over 84 months'), findsOneWidget);
    expect(find.text('EASIEST'), findsOneWidget);
    await tester.tap(find.text('Apply').last);
    expect(applied?.key, 'loan_amount');
  });

  testWidgets('approval path shows headroom when the loan qualifies', (tester) async {
    final ok = Advice.fromJson({
      'decision': 'APPROVE', 'qualifies': true, 'fraud_blocked': false,
      'message': 'You qualify.', 'max_loan_amount': 2000000, 'has_headroom': true, 'options': [],
    });
    await tester.pumpWidget(wrap(ApprovalPathCard(advice: ok)));
    expect(find.text('Qualifies for automatic approval'), findsOneWidget);
    expect(find.textContaining('20,00,000'), findsOneWidget);
  });

  testWidgets('fraud-blocked advice offers no options', (tester) async {
    final blocked = Advice.fromJson({
      'decision': 'REJECT', 'qualifies': false, 'fraud_blocked': true,
      'message': 'Flagged for possible fraud.', 'options': [],
    });
    await tester.pumpWidget(wrap(ApprovalPathCard(advice: blocked, onApply: (_) {})));
    expect(find.text('Flagged for possible fraud.'), findsOneWidget);
    expect(find.text('Apply'), findsNothing);
  });
}
