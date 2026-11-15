import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/insights.dart';
import '../models/risk_result.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/realtime_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/insights_widgets.dart';
import '../widgets/report_widgets.dart';
import '../widgets/risk_gauge.dart';

/// Full report for a saved application. Refreshes itself live when an
/// officer reviews it; officers can approve / reject from here.
class ResultScreen extends StatefulWidget {
  final int? applicationId;
  final RiskResult? initial;
  final bool justSubmitted;

  const ResultScreen({super.key, this.applicationId, this.initial, this.justSubmitted = false})
      : assert(applicationId != null || initial != null);

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  RiskResult? _r;
  bool _loading = false;
  String? _error;
  bool _updatedLive = false;
  StreamSubscription<LiveEvent>? _sub;

  final _notes = TextEditingController();
  bool _reviewing = false;

  Advice? _advice;
  String? _adviceError;

  @override
  void initState() {
    super.initState();
    _r = widget.initial;
    _notes.text = _r?.reviewerNotes ?? '';
    // List items don't carry the full report, so fetch details if missing.
    if (widget.applicationId != null && (_r == null || _r!.factors.isEmpty)) {
      _load();
    } else {
      Timer.run(_loadAdvice);
    }
    _sub = context.read<RealtimeService>().events.listen((e) {
      if (e.type == 'application.updated' && e.applicationId == widget.applicationId) {
        _load(live: true);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load({bool live = false}) async {
    setState(() => _loading = _r == null);
    try {
      final r = await ApiService.getApplication(widget.applicationId!);
      if (!mounted) return;
      setState(() {
        _r = r;
        _error = null;
        if (live) _updatedLive = true;
        if (!_reviewing) _notes.text = r.reviewerNotes ?? '';
      });
      if (_advice == null) _loadAdvice();
      if (live) {
        Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _updatedLive = false);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAdvice() async {
    final f = _r?.features;
    if (f == null || f.isEmpty) return;
    try {
      final a = await ApiService.advice(f);
      if (mounted) setState(() => _advice = a);
    } catch (e) {
      if (mounted) setState(() => _adviceError = e.toString());
    }
  }

  Future<void> _review(String status) async {
    setState(() => _reviewing = true);
    try {
      final r = await ApiService.review(_r!.id!, status, _notes.text.trim());
      if (!mounted) return;
      setState(() => _r = r);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Marked as ${Tone.status(context, status).label.toLowerCase()} — '
              'the applicant has been notified')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  Future<void> _confirmWithdraw() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw this application?'),
        content: const Text(
            'It will be removed from the review queue. You can submit a new application later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Withdraw')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _reviewing = true);
    try {
      final r = await ApiService.withdraw(_r!.id!);
      if (mounted) setState(() => _r = r);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      appBar: AppBar(
        title: Text(r?.id != null ? 'Application #${r!.id}' : 'Risk report'),
        actions: const [LiveIndicator()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : r == null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: MessageBanner(_error ?? 'Not found', onRetry: _load)))
              : RefreshIndicator(
                  onRefresh: widget.applicationId != null ? _load : () async {},
                  child: _body(context, r),
                ),
    );
  }

  Widget _body(BuildContext context, RiskResult r) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final isAdmin = context.watch<AuthService>().isAdmin;

    final left = <Widget>[
      if (widget.justSubmitted) ...[
        const MessageBanner(
          'Application submitted. Any decision by a bank officer will appear here instantly.',
          isError: false,
        ),
        const SizedBox(height: 14),
      ],
      _statusHeader(context, r),
      const SizedBox(height: 14),
      if (!isAdmin && r.isSaved && r.status == 'PENDING') ...[
        OutlinedButton.icon(
          onPressed: _reviewing ? null : _confirmWithdraw,
          icon: const Icon(Icons.undo_rounded),
          label: const Text('Withdraw application'),
        ),
        const SizedBox(height: 14),
      ],
      if (isAdmin && r.isSaved && r.status != 'WITHDRAWN') ...[
        _reviewPanel(context, r),
        const SizedBox(height: 14),
      ],
      _scoreCard(context, r),
      const SizedBox(height: 14),
      SectionCard(
        title: 'Key factors',
        icon: Icons.insights_rounded,
        child: Column(children: [for (final f in r.factors) FactorRow(f)]),
      ),
      if (r.features.isNotEmpty && r.status != 'WITHDRAWN') ...[
        const SizedBox(height: 14),
        ApprovalPathCard(advice: _advice, error: _adviceError),
      ],
    ];

    final right = <Widget>[
      _detailsCard(context, r),
      const SizedBox(height: 14),
      _checksCard(context, r),
      const SizedBox(height: 14),
      if (r.isSaved) ...[
        SectionCard(title: 'Timeline', icon: Icons.timeline_rounded, child: Timeline(_timeline(context, r))),
        const SizedBox(height: 14),
        AuditTrailCard(applicationId: r.id!, refreshKey: '${r.status}|${r.reviewedAt}'),
        const SizedBox(height: 14),
      ],
      if (r.reportSummary.isNotEmpty)
        SectionCard(
          title: 'AI summary',
          icon: Icons.summarize_outlined,
          child: Text(r.reportSummary, style: const TextStyle(height: 1.55, fontSize: 13)),
        ),
    ];

    if (wide) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
              const SizedBox(width: 20),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
            ]),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Constrained(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [...left, const SizedBox(height: 14), ...right, const SizedBox(height: 24)],
          ),
        ),
      ],
    );
  }

  Widget _statusHeader(BuildContext context, RiskResult r) {
    final tone = r.isSaved ? Tone.status(context, r.status) : Tone.decision(context, r.decision);
    final p = context.palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _updatedLive ? tone.fg : Colors.transparent, width: 2),
      ),
      child: Row(children: [
        Icon(tone.icon, color: tone.fg, size: 36),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tone.label,
                style: TextStyle(color: tone.fg, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              r.status == 'WITHDRAWN'
                  ? 'Withdrawn by the applicant'
                  : r.isReviewed
                      ? 'Reviewed by ${r.reviewerEmail ?? 'an officer'} · ${relativeTime(r.reviewedAt)}'
                      : (r.status == 'PENDING'
                          ? 'Waiting for a bank officer to review'
                          : 'Decided automatically by the AI'),
              style: TextStyle(color: tone.fg.withValues(alpha: 0.85), fontSize: 13),
            ),
          ]),
        ),
        if (_updatedLive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: p.info, borderRadius: BorderRadius.circular(8)),
            child: Text('UPDATED',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800, color: context.colors.surface)),
          ),
      ]),
    );
  }

  Widget _scoreCard(BuildContext context, RiskResult r) {
    final p = context.palette;
    return SectionCard(
      title: 'AI assessment',
      icon: Icons.psychology_alt_outlined,
      child: Column(children: [
        RiskGauge(score: r.riskScore),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          ToneChip(Tone.risk(context, r.riskLevel)),
          ToneChip(Tone(context.colors.primary, context.colors.primary.withValues(alpha: 0.12),
              Icons.smart_toy_outlined, 'AI: ${Tone.decision(context, r.decision).label}')),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: MiniMetric(label: 'New EMI', value: inr(r.newEmi))),
          Expanded(child: MiniMetric(
              label: 'Debt-to-income',
              value: pct(r.dti),
              color: r.dti > 0.5 ? p.danger : (r.dti > 0.35 ? p.warning : p.success))),
          Expanded(child: MiniMetric(label: 'Confidence', value: pct(r.confidence))),
        ]),
      ]),
    );
  }

  Widget _detailsCard(BuildContext context, RiskResult r) {
    final f = r.features;
    String yrs(dynamic v) => v is num ? '${v.toStringAsFixed(0)} yrs' : '–';
    final rows = <(String, String)>[
      ('Applicant', r.applicantName),
      if (r.applicantEmail != null) ('Account', r.applicantEmail!),
      ('Monthly income', inr(r.monthlyIncome)),
      ('Loan amount', inr(r.loanAmount)),
      ('Existing EMIs', inr(r.existingEmis)),
      ('Credit score', r.creditScore.toStringAsFixed(0)),
      ('Employment', yrs(f['employment_years'])),
      if (f['num_dependents'] is num) ('Dependents', (f['num_dependents'] as num).toStringAsFixed(0)),
      if (r.loanCategory != null) ('Purpose', r.loanCategory!),
      if ((r.tenureMonths ?? 0) > 0) ('Tenure', '${r.tenureMonths} months'),
      if (f['interest_rate'] is num) ('Interest rate', '${f['interest_rate']}%'),
      if (r.fileName != null) ('Source document', r.fileName!),
      if (r.timestamp != null) ('Submitted', dateTime(r.timestamp)),
    ];
    return SectionCard(
      title: 'Application details',
      icon: Icons.receipt_long_outlined,
      child: Column(children: [
        for (final (k, v) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 140, child: Text(k, style: TextStyle(color: context.palette.muted, fontSize: 13))),
              Expanded(child: Text(v, textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            ]),
          ),
      ]),
    );
  }

  Widget _checksCard(BuildContext context, RiskResult r) {
    final bias = r.biasReport;
    final biasNotes = (bias?['assessment'] as List?)?.cast<String>() ?? const [];
    return SectionCard(
      title: 'Compliance, fraud & fairness',
      icon: Icons.verified_user_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (r.checks.isNotEmpty)
          for (final c in r.checks) CheckRow(label: c.rule, passed: c.passed, trailing: c.code)
        else
          CheckRow(label: 'Regulatory compliance', passed: r.compliant),
        CheckRow(label: 'No fraud indicators', passed: !r.fraudFlag),
        if (bias != null) CheckRow(label: 'No bias detected', passed: bias['bias_detected'] != true),
        for (final w in [...r.fraudReasons, ...r.violations])
          Padding(padding: const EdgeInsets.only(top: 8), child: MessageBanner(w)),
        if (!r.fraudFlag && r.fraudWarnings.isNotEmpty)
          for (final w in r.fraudWarnings)
            Padding(padding: const EdgeInsets.only(top: 8), child: MessageBanner(w, isError: false)),
        if (bias != null && bias['bias_detected'] == true)
          for (final n in biasNotes)
            Padding(padding: const EdgeInsets.only(top: 8), child: MessageBanner(n, isError: false)),
      ]),
    );
  }

  List<TimelineStep> _timeline(BuildContext context, RiskResult r) {
    final p = context.palette;
    final finalTone = Tone.status(context, r.status);
    return [
      TimelineStep('Submitted', subtitle: dateTime(r.timestamp)),
      TimelineStep('AI assessment: ${Tone.decision(context, r.decision).label}',
          subtitle: 'Risk score ${r.riskScore.toStringAsFixed(0)}/100'),
      if (r.status == 'WITHDRAWN')
        TimelineStep('Withdrawn by applicant', color: finalTone.fg)
      else if (r.isReviewed)
        TimelineStep('Officer decision: ${finalTone.label}',
            subtitle: [dateTime(r.reviewedAt), if (r.reviewerNotes != null) '“${r.reviewerNotes}”']
                .join('\n'),
            color: finalTone.fg)
      else if (r.status == 'PENDING')
        TimelineStep('Awaiting officer review', done: false, color: p.warning)
      else
        TimelineStep('Final: ${finalTone.label}', color: finalTone.fg),
    ];
  }

  Widget _reviewPanel(BuildContext context, RiskResult r) {
    final p = context.palette;
    return SectionCard(
      title: 'Officer review',
      icon: Icons.gavel_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
              hintText: 'Notes for the applicant (optional)', alignLabelWithHint: true),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: p.success, foregroundColor: Colors.white),
              onPressed: _reviewing || r.status == 'APPROVED' ? null : () => _review('APPROVED'),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Approve'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white),
              onPressed: _reviewing || r.status == 'REJECTED' ? null : () => _review('REJECTED'),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Reject'),
            ),
          ),
        ]),
        if (r.status != 'PENDING')
          TextButton(
            onPressed: _reviewing ? null : () => _review('PENDING'),
            child: const Text('Move back to pending'),
          ),
      ]),
    );
  }
}
