import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/applications_controller.dart';
import '../services/realtime_service.dart';
import '../widgets/applications_list.dart';
import '../widgets/common.dart';

/// All of the applicant's applications, kept up to date live.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final ApplicationsController _c =
      ApplicationsController(context.read<RealtimeService>())..load();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My applications'), actions: const [LiveIndicator()]),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) => RefreshIndicator(
          onRefresh: _c.load,
          child: Constrained(
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  sliver: SliverToBoxAdapter(child: ApplicationsFilterBar(controller: _c)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverApplicationsList(
                    controller: _c,
                    emptyMessage: 'Applications you submit will show up here with live status.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
