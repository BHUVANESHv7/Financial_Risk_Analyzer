import 'package:flutter/material.dart';

import '../models/risk_result.dart';
import '../theme/app_theme.dart';

class MiniMetric extends StatelessWidget {
  final String label, value;
  final Color? color;
  const MiniMetric({super.key, required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Text(value,
            key: ValueKey(value),
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
      ),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 11, color: context.palette.muted)),
    ]);
  }
}

class FactorRow extends StatelessWidget {
  final RiskFactor factor;
  const FactorRow(this.factor, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, color) = switch (factor.impact) {
      'positive' => (Icons.trending_down_rounded, p.success),
      'negative' => (Icons.trending_up_rounded, p.danger),
      _ => (Icons.remove_rounded, p.muted),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(factor.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(factor.detail, style: TextStyle(fontSize: 12, color: p.muted)),
          ]),
        ),
        Text(factor.value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: color)),
      ]),
    );
  }
}

class CheckRow extends StatelessWidget {
  final String label;
  final bool passed;
  final String? trailing;
  const CheckRow({super.key, required this.label, required this.passed, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 18, color: passed ? p.success : p.danger),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 12, color: p.muted)),
      ]),
    );
  }
}

class TimelineStep {
  final String title;
  final String? subtitle;
  final bool done;
  final Color? color;
  const TimelineStep(this.title, {this.subtitle, this.done = true, this.color});
}

class Timeline extends StatelessWidget {
  final List<TimelineStep> steps;
  const Timeline(this.steps, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(children: [
      for (var i = 0; i < steps.length; i++)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Column(children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: steps[i].done ? (steps[i].color ?? context.colors.primary) : Colors.transparent,
                  border: Border.all(
                      color: steps[i].done ? (steps[i].color ?? context.colors.primary) : p.border,
                      width: 2),
                ),
              ),
              if (i < steps.length - 1)
                Expanded(child: Container(width: 2, color: p.border)),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(steps[i].title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: steps[i].done ? null : p.muted)),
                  if (steps[i].subtitle != null)
                    Text(steps[i].subtitle!, style: TextStyle(fontSize: 12, color: p.muted)),
                ]),
              ),
            ),
          ]),
        ),
    ]);
  }
}
