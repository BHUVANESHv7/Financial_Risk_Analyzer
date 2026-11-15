import 'package:flutter/material.dart';

import '../models/insights.dart';
import '../models/risk_result.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'common.dart';

IconData _leverIcon(String key) => switch (key) {
      'loan_amount' => Icons.savings_outlined,
      'tenure_months' => Icons.event_repeat_rounded,
      'existing_emis' => Icons.credit_card_off_outlined,
      'monthly_income' => Icons.group_add_outlined,
      'credit_score' => Icons.trending_up_rounded,
      _ => Icons.tune_rounded,
    };

/// Small gradient badge used to mark AI-generated insight cards.
class AiBadge extends StatelessWidget {
  final String label;
  const AiBadge({super.key, this.label = 'AI'});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: [c.primary, c.tertiary]),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_awesome, size: 12, color: c.onPrimary),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c.onPrimary)),
      ]),
    );
  }
}

/// "Path to approval": the smallest change that would get automatic approval.
class ApprovalPathCard extends StatelessWidget {
  final Advice? advice;
  final bool loading;
  final String? error;

  /// When set, each option gets an "Apply" button (live what-if screen).
  final void Function(AdviceOption option)? onApply;
  final String applyLabel;

  const ApprovalPathCard({
    super.key,
    required this.advice,
    this.loading = false,
    this.error,
    this.onApply,
    this.applyLabel = 'Apply',
  });

  @override
  Widget build(BuildContext context) {
    final a = advice;
    final p = context.palette;
    return SectionCard(
      title: 'Path to approval',
      icon: Icons.route_rounded,
      trailing: loading
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const AiBadge(),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 250),
        alignment: Alignment.topCenter,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (error != null)
            MessageBanner(error!)
          else if (a == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Working out what would get this approved…',
                  style: TextStyle(color: p.muted, fontSize: 13)),
            )
          else if (a.fraudBlocked)
            MessageBanner(a.message)
          else if (a.qualifies) ...[
            Row(children: [
              Icon(Icons.verified_rounded, color: p.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Qualifies for automatic approval',
                    style: TextStyle(fontWeight: FontWeight.w700, color: p.success)),
              ),
            ]),
            if (a.maxLoanAmount != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: p.successBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Approval headroom', style: TextStyle(fontSize: 12, color: p.muted)),
                      const SizedBox(height: 2),
                      Text('Up to ${inr(a.maxLoanAmount!)}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(a.hasHeadroom ? 'on the same terms' : 'You are at the maximum for these terms',
                          style: TextStyle(fontSize: 12, color: p.muted)),
                    ]),
                  ),
                  if (onApply != null && a.hasHeadroom)
                    TextButton(
                      onPressed: () => onApply!(AdviceOption(
                        key: 'loan_amount',
                        title: '',
                        detail: '',
                        value: a.maxLoanAmount!,
                        newRiskScore: 0,
                        newRiskLevel: 'LOW',
                        newEmi: 0,
                        effort: 0,
                      )),
                      child: const Text('Use max'),
                    ),
                ]),
              ),
            ],
          ] else ...[
            Text(a.message, style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
            const SizedBox(height: 6),
            for (final (i, o) in a.options.indexed) _OptionTile(
              option: o,
              best: i == 0,
              onApply: onApply == null ? null : () => onApply!(o),
              applyLabel: applyLabel,
            ),
          ],
        ]),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final AdviceOption option;
  final bool best;
  final VoidCallback? onApply;
  final String applyLabel;

  const _OptionTile({required this.option, required this.best, this.onApply, required this.applyLabel});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: best ? c.primary.withValues(alpha: 0.5) : p.border),
        color: best ? c.primary.withValues(alpha: 0.05) : null,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_leverIcon(option.key), size: 20, color: c.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(option.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (best)
                Text('EASIEST',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: c.primary)),
            ]),
            const SizedBox(height: 3),
            Text(option.detail, style: TextStyle(fontSize: 12, color: p.muted, height: 1.35)),
            const SizedBox(height: 6),
            Text('New risk score ${option.newRiskScore.toStringAsFixed(0)} · EMI ${inr(option.newEmi)}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.success)),
          ]),
        ),
        if (onApply != null) ...[
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: onApply, child: Text(applyLabel)),
        ],
      ]),
    );
  }
}

String _actionLabel(String action) => switch (action) {
      'CREATED' => 'Application submitted',
      'REVIEWED' => 'Officer review',
      'WITHDRAWN' => 'Withdrawn',
      'IMPORTED' => 'Imported into ledger',
      _ => action,
    };

/// Tamper-evident audit trail of one application, with chain verification.
class AuditTrailCard extends StatefulWidget {
  final int applicationId;

  /// Change this value to reload (e.g. after a live update).
  final Object? refreshKey;

  const AuditTrailCard({super.key, required this.applicationId, this.refreshKey});

  @override
  State<AuditTrailCard> createState() => _AuditTrailCardState();
}

class _AuditTrailCardState extends State<AuditTrailCard> {
  AuditTrail? _trail;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AuditTrailCard old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey || old.applicationId != widget.applicationId) _load();
  }

  Future<void> _load() async {
    try {
      final t = await ApiService.audit(widget.applicationId);
      if (!mounted) return;
      setState(() {
        _trail = t;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = _trail;
    final badge = t == null
        ? null
        : t.verified
            ? Tone(p.success, p.successBg, Icons.shield_rounded, 'Verified')
            : Tone(p.danger, p.dangerBg, Icons.gpp_bad_rounded, 'Tampered');
    return SectionCard(
      title: 'Audit trail',
      icon: Icons.link_rounded,
      trailing: badge == null ? null : ToneChip(badge, dense: true),
      child: _error != null
          ? MessageBanner(_error!, onRetry: _load)
          : t == null
              ? const Padding(
                  padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(
                    'Every change is sealed with a SHA-256 hash linked to the previous one, '
                    'so no record can be edited or deleted unnoticed.',
                    style: TextStyle(fontSize: 12, color: p.muted, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  for (final (i, e) in t.events.indexed)
                    _AuditRow(event: e, last: i == t.events.length - 1),
                ]),
    );
  }
}

class _AuditRow extends StatelessWidget {
  final AuditEvent event;
  final bool last;
  const _AuditRow({required this.event, required this.last});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = event;
    final color = e.verified ? p.success : p.danger;
    final status = e.data['status']?.toString();
    final notes = e.data['notes']?.toString();
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 22,
          child: Column(children: [
            Container(
              margin: const EdgeInsets.only(top: 3),
              width: 12,
              height: 12,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            if (!last) Expanded(child: Container(width: 2, color: p.border)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                [_actionLabel(e.action), if (e.action == 'REVIEWED' && status != null) '→ $status']
                    .join(' '),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                [e.actorEmail ?? 'system', dateTime(e.timestamp)].join(' · '),
                style: TextStyle(fontSize: 12, color: p.muted),
              ),
              if (notes != null && notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('“$notes”', style: TextStyle(fontSize: 12, color: p.muted)),
                ),
              const SizedBox(height: 4),
              Tooltip(
                message: 'Hash ${e.hash}\nPrevious ${e.prevHash}',
                child: Text(
                  '#${e.hash.substring(0, 12)}  ${e.verified ? 'intact' : 'MODIFIED'}',
                  style: TextStyle(
                      fontFamily: 'monospace', fontSize: 11, color: color, letterSpacing: 0.3),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Officer card: model drift (PSI) and audit-ledger integrity.
class ModelHealthCard extends StatefulWidget {
  final Object? refreshKey;
  const ModelHealthCard({super.key, this.refreshKey});

  @override
  State<ModelHealthCard> createState() => _ModelHealthCardState();
}

class _ModelHealthCardState extends State<ModelHealthCard> {
  ModelHealth? _health;
  Map<String, dynamic>? _ledger;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ModelHealthCard old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final results = await Future.wait([ApiService.modelHealth(), ApiService.verifyLedger()]);
      if (!mounted) return;
      setState(() {
        _health = results[0] as ModelHealth;
        _ledger = results[1] as Map<String, dynamic>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Tone _tone(BuildContext context, String status) {
    final p = context.palette;
    return switch (status) {
      'stable' => Tone(p.success, p.successBg, Icons.check_circle_rounded, 'Stable'),
      'moderate' => Tone(p.warning, p.warningBg, Icons.info_rounded, 'Shifting'),
      'significant' => Tone(p.danger, p.dangerBg, Icons.warning_rounded, 'Drifted'),
      _ => Tone(p.muted, p.surfaceAlt, Icons.hourglass_empty_rounded, 'Collecting data'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final h = _health;
    final ledger = _ledger;
    return SectionCard(
      title: 'AI model health',
      icon: Icons.monitor_heart_outlined,
      trailing: IconButton(
        tooltip: 'Re-check',
        visualDensity: VisualDensity.compact,
        onPressed: _busy ? null : _load,
        icon: _busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh_rounded, size: 20),
      ),
      child: _error != null
          ? MessageBanner(_error!, onRetry: _load)
          : h == null
              ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    ToneChip(_tone(context, h.status)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Last ${h.sampleSize} applications vs. training data',
                          style: TextStyle(fontSize: 12, color: p.muted)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text(h.message, style: const TextStyle(fontSize: 13, height: 1.4)),
                  if (h.hasData) ...[
                    const SizedBox(height: 12),
                    for (final f in h.features.take(5)) _DriftBar(f, _tone(context, f.status).fg),
                    Text('Population Stability Index · under 0.10 stable, over 0.25 drifted',
                        style: TextStyle(fontSize: 11, color: p.muted)),
                  ],
                  if (ledger != null) ...[
                    const Divider(height: 24),
                    Row(children: [
                      Icon(ledger['valid'] == true ? Icons.shield_rounded : Icons.gpp_bad_rounded,
                          color: ledger['valid'] == true ? p.success : p.danger, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ledger['valid'] == true
                              ? 'Audit ledger intact · ${ledger['events']} sealed events'
                              : 'Audit ledger broken at event #${ledger['broken_at']}: ${ledger['reason']}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: ledger['valid'] == true ? null : p.danger),
                        ),
                      ),
                    ]),
                  ],
                ]),
    );
  }
}

class _DriftBar extends StatelessWidget {
  final FeatureDrift f;
  final Color color;
  const _DriftBar(this.f, this.color);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(width: 130, child: Text(f.label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (f.psi / 0.5).clamp(0.02, 1.0),
              minHeight: 8,
              color: color,
              backgroundColor: p.border,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(f.psi.toStringAsFixed(2),
              textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: p.muted)),
        ),
      ]),
    );
  }
}
