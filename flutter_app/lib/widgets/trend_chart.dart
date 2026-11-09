import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

/// Stacked daily bars (approved / pending / rejected) for the dashboard.
class TrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> days;
  const TrendChart({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final maxTotal = days.fold<int>(1, (m, d) => (d['total'] as int) > m ? d['total'] as int : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in days)
                Expanded(
                  child: Tooltip(
                    message: '${_label(d['date'])}: ${d['total']} applications',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _Bar(day: d, max: maxTotal, palette: p),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_label(days.first['date']), style: TextStyle(fontSize: 11, color: p.muted)),
            Text('Today', style: TextStyle(fontSize: 11, color: p.muted)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 14, children: [
          _Legend(color: p.success, label: 'Approved'),
          _Legend(color: p.warning, label: 'Pending'),
          _Legend(color: p.danger, label: 'Rejected'),
        ]),
      ],
    );
  }

  static String _label(dynamic iso) {
    final d = DateTime.tryParse(iso.toString());
    return d == null ? '' : DateFormat('d MMM').format(d);
  }
}

class _Bar extends StatelessWidget {
  final Map<String, dynamic> day;
  final int max;
  final Palette palette;
  const _Bar({required this.day, required this.max, required this.palette});

  @override
  Widget build(BuildContext context) {
    final segments = [
      (day['REJECTED'] as int? ?? 0, palette.danger),
      (day['PENDING'] as int? ?? 0, palette.warning),
      (day['APPROVED'] as int? ?? 0, palette.success),
    ];
    return LayoutBuilder(builder: (context, c) {
      final total = day['total'] as int? ?? 0;
      if (total == 0) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(height: 3, decoration: BoxDecoration(
            color: palette.border, borderRadius: BorderRadius.circular(2))),
        );
      }
      final h = c.maxHeight * total / max;
      return Align(
        alignment: Alignment.bottomCenter,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          height: h,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
          child: Column(
            children: [
              for (final (n, color) in segments)
                if (n > 0) Expanded(flex: n, child: Container(color: color)),
            ],
          ),
        ),
      );
    });
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: context.palette.muted)),
      ]);
}
