import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_app/models/risk_result.dart';
import 'package:loan_app/theme/app_theme.dart';
import 'package:loan_app/widgets/common.dart';
import 'package:loan_app/widgets/risk_gauge.dart';

Widget wrap(Widget child, {bool dark = false}) => MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('risk gauge animates to and shows the score', (tester) async {
    await tester.pumpWidget(wrap(const RiskGauge(score: 42)));
    await tester.pumpAndSettle();
    expect(find.text('42'), findsOneWidget);
    expect(find.text('risk score'), findsOneWidget);
  });

  testWidgets('status tones have readable labels in both themes', (tester) async {
    for (final dark in [false, true]) {
      late Map<String, String> labels;
      await tester.pumpWidget(wrap(Builder(builder: (context) {
        labels = {
          for (final s in ['APPROVED', 'REJECTED', 'PENDING', 'WITHDRAWN'])
            s: Tone.status(context, s).label,
        };
        return const SizedBox();
      }), dark: dark));
      expect(labels, {
        'APPROVED': 'Approved',
        'REJECTED': 'Rejected',
        'PENDING': 'Pending review',
        'WITHDRAWN': 'Withdrawn',
      });
    }
  });

  testWidgets('application tile shows status and NEW badge when highlighted', (tester) async {
    final app = RiskResult.fromJson({
      'id': 1,
      'applicant_name': 'Neha Kapoor',
      'risk_level': 'LOW',
      'risk_score': 18,
      'decision': 'APPROVE',
      'status': 'APPROVED',
      'loan_amount': 500000,
      'loan_category': 'Personal',
    });
    var tapped = false;
    await tester.pumpWidget(wrap(SizedBox(
      width: 500,
      child: ApplicationTile(app: app, highlight: true, onTap: () => tapped = true),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Neha Kapoor'), findsOneWidget);
    expect(find.text('18'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('NEW'), findsOneWidget);
    await tester.tap(find.text('Neha Kapoor'));
    expect(tapped, isTrue);
  });
}
