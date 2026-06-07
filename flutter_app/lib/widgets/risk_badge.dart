import 'package:flutter/material.dart';
import '../models/risk_result.dart';

class RiskBadge extends StatelessWidget {
  final String level;
  final double fontSize;

  const RiskBadge({super.key, required this.level, this.fontSize = 14});

  @override
  Widget build(BuildContext context) {
    final meta = RiskResult.riskMeta(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: meta['bg'] as Color,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: (meta['color'] as Color).withOpacity(0.4)),
      ),
      child: Text(
        meta['label'] as String,
        style: TextStyle(
          color: meta['color'] as Color,
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
      ),
    );
  }
}

class DecisionBadge extends StatelessWidget {
  final String decision;

  const DecisionBadge({super.key, required this.decision});

  @override
  Widget build(BuildContext context) {
    final meta = RiskResult.decisionMeta(decision);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: meta['bg'] as Color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (meta['color'] as Color).withValues(alpha: 0.5), width: 1.5),
      ),
      child: Text(
        decision.toUpperCase(),
        style: TextStyle(
          color: meta['color'] as Color,
          fontWeight: FontWeight.bold,
          fontSize: 16,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF374151), fontSize: 14)),
          Text(value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: valueColor ?? const Color(0xFF111827),
              )),
        ],
      ),
    );
  }
}
