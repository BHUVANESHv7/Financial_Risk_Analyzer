import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/risk_result.dart';
import '../services/realtime_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Max content width so the layout looks good on web/desktop as well as phones.
class Constrained extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const Constrained({super.key, required this.child, this.maxWidth = 760});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

class SectionCard extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  const SectionCard({
    super.key,
    this.title,
    this.icon,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: context.colors.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(title!,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                if (trailing != null) trailing!,
              ]),
              const SizedBox(height: 14),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class ToneChip extends StatelessWidget {
  final Tone tone;
  final bool dense;
  final bool showIcon;
  const ToneChip(this.tone, {super.key, this.dense = false, this.showIcon = true});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 12, vertical: dense ? 3 : 6),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (showIcon) ...[
          Icon(tone.icon, size: dense ? 12 : 15, color: tone.fg),
          SizedBox(width: dense ? 4 : 6),
        ],
        Text(tone.label,
            style: TextStyle(
                color: tone.fg, fontWeight: FontWeight.w700, fontSize: dense ? 11 : 13)),
      ]),
    );
  }
}

/// Green "Live" dot when the WebSocket is connected. Tap to reconnect.
class LiveIndicator extends StatelessWidget {
  final bool showLabel;
  const LiveIndicator({super.key, this.showLabel = true});

  @override
  Widget build(BuildContext context) {
    final rt = context.watch<RealtimeService>();
    final p = context.palette;
    final (color, label) = switch (rt.status) {
      LiveStatus.live => (p.success, 'Live'),
      LiveStatus.connecting => (p.warning, 'Connecting'),
      LiveStatus.offline => (p.danger, 'Offline'),
    };
    return Tooltip(
      message: rt.isLive ? 'Receiving real-time updates' : 'Tap to reconnect',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: rt.isLive ? null : rt.reconnectNow,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _PulseDot(color: color, pulsing: rt.isLive),
            if (showLabel) ...[
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  final bool pulsing;
  const _PulseDot({required this.color, required this.pulsing});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 2));

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _c.repeat();
  }

  @override
  void didUpdateWidget(_PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_c.isAnimating) _c.repeat();
    if (!widget.pulsing) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Stack(alignment: Alignment.center, children: [
          if (widget.pulsing)
            Container(
              width: 6 + 8 * _c.value,
              height: 6 + 8 * _c.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.35 * (1 - _c.value)),
              ),
            ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
          ),
        ]),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final String? hint;
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: color),
            ),
            const Spacer(),
            if (hint != null) Text(hint!, style: TextStyle(fontSize: 11, color: p.muted)),
          ]),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a),
                    child: c)),
            child: Text(value,
                key: ValueKey(value),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: p.muted)),
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 48, color: p.muted),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

class MessageBanner extends StatelessWidget {
  final String message;
  final bool isError;
  final VoidCallback? onRetry;
  const MessageBanner(this.message, {super.key, this.isError = true, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = isError ? p.danger : p.info;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? p.dangerBg : p.infoBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(isError ? Icons.error_outline : Icons.info_outline, color: fg, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: TextStyle(color: fg, fontSize: 13))),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: Text('Retry', style: TextStyle(color: fg))),
      ]),
    );
  }
}

/// One row in an applications list. [highlight] flashes for live-arrived items.
class ApplicationTile extends StatelessWidget {
  final RiskResult app;
  final bool showApplicant;
  final bool highlight;
  final VoidCallback onTap;

  const ApplicationTile({
    super.key,
    required this.app,
    required this.onTap,
    this.showApplicant = false,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final risk = Tone.risk(context, app.riskLevel);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      decoration: BoxDecoration(
        color: highlight ? p.infoBg : context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ? p.info : p.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: risk.bg,
              child: Text(
                app.riskScore.toStringAsFixed(0),
                style: TextStyle(color: risk.fg, fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(app.applicantName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (app.fraudFlag) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.gpp_maybe_rounded, size: 16, color: p.danger),
                  ],
                  if (highlight) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: p.info, borderRadius: BorderRadius.circular(6)),
                      child: Text('NEW',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: context.colors.surface)),
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(
                  [
                    inrCompact(app.loanAmount),
                    if (app.loanCategory != null) app.loanCategory!,
                    if (showApplicant && app.applicantEmail != null) app.applicantEmail!,
                    relativeTime(app.timestamp),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.muted),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            ToneChip(Tone.status(context, app.status), dense: true),
          ]),
        ),
      ),
    );
  }
}
