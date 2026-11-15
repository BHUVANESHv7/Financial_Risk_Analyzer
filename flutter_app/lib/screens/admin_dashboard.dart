import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/applications_controller.dart';
import '../services/api_service.dart';
import '../services/realtime_service.dart';
import '../utils/download.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/applications_list.dart';
import '../widgets/common.dart';
import '../widgets/trend_chart.dart';
import 'app_menu.dart';

/// Bank officer dashboard: live KPIs, trend, risk mix and the review queue.
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late final ApplicationsController _c = ApplicationsController(
    context.read<RealtimeService>(),
    withStats: true,
  )
    ..status = 'PENDING' // open on the review queue
    ..load();

  bool _exporting = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!canSaveFiles) {
      messenger.showSnackBar(const SnackBar(content: Text('CSV export is available in the web app.')));
      return;
    }
    setState(() => _exporting = true);
    try {
      final (name, bytes) =
          await ApiService.exportCsv(status: _c.status, risk: _c.risk, fraud: _c.fraud);
      await saveFile(name, bytes, 'text/csv');
      messenger.showSnackBar(SnackBar(content: Text('Downloaded $name')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rt = context.watch<RealtimeService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Officer dashboard'),
        actions: [
          if (rt.isLive)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'People connected right now',
                child: Chip(
                  avatar: const Icon(Icons.people_alt_outlined, size: 16),
                  label: Text('${rt.officersOnline} officers · ${rt.applicantsOnline} applicants'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Export current list as CSV',
            icon: _exporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_rounded),
            onPressed: _exporting ? null : _export,
          ),
          const LiveIndicator(),
          const AppMenu(),
        ],
      ),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) => RefreshIndicator(
          onRefresh: _c.load,
          child: Constrained(
            maxWidth: 1200,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(child: _overview(context)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        const Text('Applications',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 8),
                        Text('${_c.total}', style: TextStyle(color: context.palette.muted)),
                      ]),
                      const SizedBox(height: 12),
                      ApplicationsFilterBar(controller: _c, showSearch: true, showFraud: true),
                    ]),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverApplicationsList(
                    controller: _c,
                    showApplicant: true,
                    emptyMessage: 'New applications appear here the moment they are submitted.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _overview(BuildContext context) {
    final s = _c.stats;
    final p = context.palette;
    if (s == null) {
      return _c.error != null
          ? MessageBanner(_c.error!, onRetry: _c.load)
          : const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    }
    final approval = s['approval_rate'];
    final kpis = [
      StatCard(label: 'Awaiting review', value: '${s['pending']}',
          icon: Icons.hourglass_top_rounded, color: p.warning),
      StatCard(label: 'Total applications', value: '${s['total']}',
          icon: Icons.folder_copy_outlined, color: context.colors.primary),
      StatCard(label: 'Approval rate', value: approval == null ? '–' : pct(approval as num),
          icon: Icons.thumb_up_alt_outlined, color: p.success),
      StatCard(label: 'Fraud alerts', value: '${s['fraud_alerts']}',
          icon: Icons.gpp_maybe_outlined, color: p.danger),
      StatCard(label: 'Avg risk score', value: '${s['avg_risk_score'] ?? '–'}',
          icon: Icons.speed_rounded, color: p.info),
      StatCard(label: 'Total requested', value: inrCompact((s['total_requested'] as num?) ?? 0),
          icon: Icons.currency_rupee_rounded, color: p.muted),
    ];

    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 1000 ? 6 : (box.maxWidth >= 640 ? 3 : 2);
      final cardW = (box.maxWidth - (cols - 1) * 10) / cols;
      final wide = box.maxWidth >= 900;

      final trend = SectionCard(
        title: 'Last 14 days',
        icon: Icons.bar_chart_rounded,
        child: TrendChart(days: (s['trend'] as List).cast<Map<String, dynamic>>()),
      );
      final mix = SectionCard(
        title: 'Risk mix',
        icon: Icons.donut_small_outlined,
        child: _RiskMix(byRisk: (s['by_risk'] as Map).cast<String, dynamic>()),
      );

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final k in kpis) SizedBox(width: cardW, child: k),
        ]),
        const SizedBox(height: 14),
        if (wide)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 3, child: trend),
              const SizedBox(width: 14),
              Expanded(flex: 2, child: mix),
            ]),
          )
        else ...[
          trend,
          const SizedBox(height: 14),
          mix,
        ],
      ]);
    });
  }
}

class _RiskMix extends StatelessWidget {
  final Map<String, dynamic> byRisk;
  const _RiskMix({required this.byRisk});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rows = [
      ('Low', (byRisk['LOW'] as int?) ?? 0, p.success),
      ('Medium', (byRisk['MEDIUM'] as int?) ?? 0, p.warning),
      ('High', (byRisk['HIGH'] as int?) ?? 0, p.danger),
    ];
    final total = rows.fold<int>(0, (s, r) => s + r.$2);
    return Column(children: [
      // Stacked proportion bar
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 14,
          child: total == 0
              ? Container(color: p.border)
              : Row(children: [
                  for (final (_, n, color) in rows)
                    if (n > 0) Expanded(flex: n, child: Container(color: color)),
                ]),
        ),
      ),
      const SizedBox(height: 16),
      for (final (label, n, color) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Container(width: 10, height: 10,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 10),
            Expanded(child: Text('$label risk')),
            Text('$n', style: const TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(
              width: 52,
              child: Text(total == 0 ? '' : pct(n / total),
                  textAlign: TextAlign.right, style: TextStyle(color: p.muted, fontSize: 12)),
            ),
          ]),
        ),
    ]);
  }
}
