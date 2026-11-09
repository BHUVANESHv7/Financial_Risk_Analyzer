import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/risk_result.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/report_widgets.dart';
import '../widgets/risk_gauge.dart';
import 'result_screen.dart';

const _categories = [
  'Personal', 'Education', 'Medical', 'Home Improvement',
  'Debt Consolidation', 'Business', 'Vehicle',
];

/// Review extracted values (or enter them manually). Every change is
/// re-scored live; nothing is saved until the user submits.
class VerifyDataScreen extends StatefulWidget {
  final RiskResult? initial;
  const VerifyDataScreen({super.key, this.initial});

  @override
  State<VerifyDataScreen> createState() => _VerifyDataScreenState();
}

class _VerifyDataScreenState extends State<VerifyDataScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _income, _loan, _emis;
  double _credit = 700, _years = 2, _deps = 1, _rate = 10.5;
  int _tenure = 60;
  String _category = 'Personal';

  RiskResult? _live;
  bool _scoring = false;
  bool _submitting = false;
  String? _error;
  Timer? _debounce;
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    final f = widget.initial?.features ?? const {};
    double n(String k, double d) => (f[k] is num) ? (f[k] as num).toDouble() : d;
    String money(String k) {
      final v = n(k, 0);
      return v == 0 ? '' : v.toStringAsFixed(0);
    }

    final name = f['applicant_name']?.toString() ?? '';
    _name = TextEditingController(text: name == 'Unknown Applicant' ? '' : name);
    _income = TextEditingController(text: money('monthly_income'));
    _loan = TextEditingController(text: money('loan_amount'));
    _emis = TextEditingController(text: money('existing_emis'));
    _credit = n('credit_score', 700).clamp(300, 900);
    _years = n('employment_years', 2).clamp(0, 40);
    _deps = n('num_dependents', 1).clamp(0, 10);
    _rate = n('interest_rate', 10.5).clamp(5, 25);
    _tenure = n('tenure_months', 60).round().clamp(6, 360);
    final cat = f['loan_category']?.toString();
    if (_categories.contains(cat)) _category = cat!;

    _live = widget.initial;
    if (widget.initial == null) {
      // Manual entry: start from sensible example values and score them.
      _income.text = '40000';
      _loan.text = '500000';
      _scoring = true;
      _debounce = Timer(Duration.zero, _rescore);
    }
    for (final c in [_income, _loan, _emis]) {
      var last = c.text;
      c.addListener(() {
        if (c.text == last) return; // ignore cursor/selection changes
        last = c.text;
        _changed();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_name, _income, _loan, _emis]) {
      c.dispose();
    }
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '')) ?? 0;

  Map<String, dynamic> get _features => {
        'applicant_name': _name.text.trim().isEmpty ? null : _name.text.trim(),
        'monthly_income': _num(_income),
        'loan_amount': _num(_loan),
        'existing_emis': _num(_emis),
        'employment_years': _years.roundToDouble(),
        'credit_score': _credit.roundToDouble(),
        'num_dependents': _deps.roundToDouble(),
        'loan_category': _category,
        'tenure_months': _tenure,
        'interest_rate': double.parse(_rate.toStringAsFixed(1)),
        if (widget.initial?.features['raw_text_length'] != null)
          'raw_text_length': widget.initial!.features['raw_text_length'],
        if (widget.initial?.fileName != null) 'source_file': widget.initial!.fileName,
      };

  /// Debounced live re-score. Out-of-order responses are ignored.
  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _rescore);
    if (!_scoring) setState(() => _scoring = true);
  }

  Future<void> _rescore() async {
    if (_num(_income) <= 0) {
      setState(() => _scoring = false);
      return;
    }
    final seq = ++_requestSeq;
    try {
      final r = await ApiService.recalculate(_features);
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _live = r;
        _error = null;
      });
    } catch (e) {
      if (mounted && seq == _requestSeq) setState(() => _error = e.toString());
    } finally {
      if (mounted && seq == _requestSeq) setState(() => _scoring = false);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final saved = await ApiService.submitApplication(_features);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => ResultScreen(applicationId: saved.id, initial: saved, justSubmitted: true)),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'Enter loan details' : 'Verify extracted data'),
      ),
      bottomNavigationBar: wide ? null : _bottomBar(context),
      body: Form(
        key: _form,
        child: wide
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 6, child: ListView(
                        padding: const EdgeInsets.all(20), children: _formChildren(context))),
                    Expanded(flex: 5, child: ListView(
                        padding: const EdgeInsets.fromLTRB(0, 20, 20, 20),
                        children: [_livePanel(context, showSubmit: true)])),
                  ]),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Constrained(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _livePanel(context, showSubmit: false),
                      const SizedBox(height: 16),
                      ..._formChildren(context),
                    ],
                  )),
                ],
              ),
      ),
    );
  }

  List<Widget> _formChildren(BuildContext context) {
    final p = context.palette;
    return [
      if (widget.initial?.fileName != null) ...[
        Card(
          child: ListTile(
            leading: Icon(Icons.description_outlined, color: context.colors.primary),
            title: Text(widget.initial!.fileName!, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: const Text('Values extracted — please check and correct them'),
            trailing: Icon(Icons.check_circle, color: p.success),
          ),
        ),
        const SizedBox(height: 16),
      ],
      SectionCard(
        title: 'Applicant & income',
        icon: Icons.person_outline,
        child: Column(children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Applicant name'),
          ),
          const SizedBox(height: 12),
          _moneyField(_income, 'Monthly net income', required: true),
          const SizedBox(height: 12),
          _moneyField(_emis, 'Existing monthly EMIs'),
          const SizedBox(height: 8),
          _slider('Employment', '${_years.round()} yrs', _years, 0, 40, 40,
              (v) => _years = v),
          _slider('Dependents', '${_deps.round()}', _deps, 0, 10, 10, (v) => _deps = v),
          _slider('Credit score (CIBIL)', '${_credit.round()}', _credit, 300, 900, 120,
              (v) => _credit = v),
        ]),
      ),
      const SizedBox(height: 16),
      SectionCard(
        title: 'Loan request',
        icon: Icons.request_quote_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _moneyField(_loan, 'Loan amount', required: true),
          const SizedBox(height: 8),
          _slider('Tenure', _tenureLabel(_tenure), _tenure.toDouble(), 6, 360, 59,
              (v) => _tenure = v.round()),
          _slider('Interest rate', '${_rate.toStringAsFixed(1)}%', _rate, 5, 25, 40,
              (v) => _rate = v),
          const SizedBox(height: 8),
          Text('Purpose', style: TextStyle(fontSize: 13, color: p.muted)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in _categories)
              ChoiceChip(
                label: Text(c),
                selected: _category == c,
                onSelected: (_) {
                  setState(() => _category = c);
                  _changed();
                },
              ),
          ]),
        ]),
      ),
      const SizedBox(height: 24),
    ];
  }

  static String _tenureLabel(int m) =>
      m % 12 == 0 ? '${m ~/ 12} yrs' : '${m ~/ 12}y ${m % 12}m';

  Widget _moneyField(TextEditingController c, String label, {bool required = false}) {
    return TextFormField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
      decoration: InputDecoration(labelText: label, prefixText: '₹ '),
      validator: required
          ? (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter an amount' : null
          : null,
    );
  }

  Widget _slider(String label, String value, double v, double min, double max, int divisions,
      void Function(double) set) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: context.palette.muted))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        Slider(
          value: v.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: (x) {
            setState(() => set(x));
            _changed();
          },
        ),
      ]),
    );
  }

  Widget _livePanel(BuildContext context, {required bool showSubmit}) {
    final r = _live;
    final p = context.palette;
    return SectionCard(
      title: 'Live assessment',
      icon: Icons.bolt_rounded,
      trailing: AnimatedOpacity(
        opacity: _scoring ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (r == null)
          const Padding(
              padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else ...[
          Center(child: RiskGauge(score: r.riskScore, busy: _scoring, size: 210)),
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
            ToneChip(Tone.risk(context, r.riskLevel)),
            ToneChip(Tone.decision(context, r.decision)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: MiniMetric(label: 'New EMI', value: inr(r.newEmi))),
            Expanded(child: MiniMetric(
                label: 'Debt-to-income',
                value: pct(r.dti),
                color: r.dti > 0.5 ? p.danger : (r.dti > 0.35 ? p.warning : p.success))),
            Expanded(child: MiniMetric(label: 'Confidence', value: pct(r.confidence))),
          ]),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 10),
          Text('What drives this score', style: TextStyle(fontSize: 13, color: p.muted)),
          const SizedBox(height: 6),
          for (final f in r.factors) FactorRow(f),
          if (r.violations.isNotEmpty || r.fraudFlag) ...[
            const SizedBox(height: 10),
            for (final v in [...r.fraudReasons, ...r.violations])
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: MessageBanner(v),
              ),
          ],
        ],
        if (_error != null) ...[const SizedBox(height: 12), MessageBanner(_error!)],
        if (showSubmit) ...[
          const SizedBox(height: 18),
          _submitButton(),
        ],
      ]),
    );
  }

  Widget _submitButton() => FilledButton.icon(
        onPressed: _submitting ? null : _submit,
        icon: _submitting
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.send_rounded),
        label: const Text('Submit application'),
      );

  Widget _bottomBar(BuildContext context) {
    final r = _live;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLowest,
          border: Border(top: BorderSide(color: context.palette.border)),
        ),
        child: Row(children: [
          if (r != null) ...[
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Score ${r.riskScore.toStringAsFixed(0)}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: Tone.risk(context, r.riskLevel).fg)),
              Text(Tone.decision(context, r.decision).label,
                  style: TextStyle(fontSize: 12, color: context.palette.muted)),
            ]),
            const SizedBox(width: 16),
          ],
          Expanded(child: _submitButton()),
        ]),
      ),
    );
  }
}
