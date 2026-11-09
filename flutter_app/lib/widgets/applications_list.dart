import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/applications_controller.dart';
import '../screens/result_screen.dart';
import 'common.dart';

/// Filter chips (+ optional search) bound to an [ApplicationsController].
class ApplicationsFilterBar extends StatefulWidget {
  final ApplicationsController controller;
  final bool showSearch;
  final bool showFraud;
  const ApplicationsFilterBar({
    super.key,
    required this.controller,
    this.showSearch = false,
    this.showFraud = false,
  });

  @override
  State<ApplicationsFilterBar> createState() => _ApplicationsFilterBarState();
}

class _ApplicationsFilterBarState extends State<ApplicationsFilterBar> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final filters = <(String, bool, VoidCallback)>[
      ('All', c.status == null && c.fraud == null, () => c.setFilter(clear: true)),
      ('Pending', c.status == 'PENDING', () => c.setFilter(clear: true, status: 'PENDING')),
      ('Approved', c.status == 'APPROVED', () => c.setFilter(clear: true, status: 'APPROVED')),
      ('Rejected', c.status == 'REJECTED', () => c.setFilter(clear: true, status: 'REJECTED')),
      if (widget.showFraud) ('Fraud alerts', c.fraud == true, () => c.setFilter(clear: true, fraud: true)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.showSearch) ...[
        TextField(
          decoration: const InputDecoration(
            hintText: 'Search by applicant name or email',
            prefixIcon: Icon(Icons.search_rounded),
          ),
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), () {
              c.search = v;
              c.load();
            });
          },
        ),
        const SizedBox(height: 12),
      ],
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final (label, selected, onTap) in filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
            ),
        ]),
      ),
    ]);
  }
}

/// Sliver list of applications with loading / empty / error states and
/// infinite scroll. Rebuilds when the controller changes.
class SliverApplicationsList extends StatelessWidget {
  final ApplicationsController controller;
  final bool showApplicant;
  final String emptyMessage;

  const SliverApplicationsList({
    super.key,
    required this.controller,
    this.showApplicant = false,
    this.emptyMessage = 'Nothing here yet.',
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.loading && c.items.isEmpty) {
      return const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())));
    }
    if (c.error != null && c.items.isEmpty) {
      return SliverToBoxAdapter(child: MessageBanner(c.error!, onRetry: c.load));
    }
    if (c.items.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyState(icon: Icons.inbox_outlined, title: 'No applications', message: emptyMessage),
      );
    }
    return SliverList.builder(
      itemCount: c.items.length + (c.hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= c.items.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) => c.loadMore());
          return const Padding(
              padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
        }
        final a = c.items[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ApplicationTile(
            key: ValueKey(a.id),
            app: a,
            showApplicant: showApplicant,
            highlight: c.highlighted.contains(a.id),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ResultScreen(applicationId: a.id, initial: a))),
          ),
        );
      },
    );
  }
}
