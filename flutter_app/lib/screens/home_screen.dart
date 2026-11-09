import 'package:camera/camera.dart' show XFile;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/applications_controller.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/realtime_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'app_menu.dart';
import 'camera_screen.dart';
import 'history_screen.dart';
import 'result_screen.dart';
import 'verify_data_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ApplicationsController _apps =
      ApplicationsController(context.read<RealtimeService>(), pageSize: 5, withStats: true)..load();

  bool _analyzing = false;
  String? _fileName;
  String? _error;

  @override
  void dispose() {
    _apps.dispose();
    super.dispose();
  }

  // ── Picking a document ─────────────────────────────────────────
  void _chooseSource() {
    setState(() => _error = null);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('Browse files'),
              subtitle: const Text('PDF, JPG or PNG — up to 10 MB'),
              onTap: () {
                Navigator.pop(ctx);
                _pickFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              subtitle: const Text('Capture a salary slip with the camera'),
              onTap: () async {
                Navigator.pop(ctx);
                final XFile? shot = await Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const CameraScreen()));
                if (shot != null) _useCameraShot(shot);
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) _analyze(result.files.first);
  }

  Future<void> _useCameraShot(XFile image) async {
    final bytes = await image.readAsBytes();
    var name = image.name;
    if (!name.contains('.') || name.toLowerCase() == 'blob') {
      name = 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg';
    }
    _analyze(PlatformFile(
        name: name, size: bytes.length, bytes: bytes, path: kIsWeb ? null : image.path));
  }

  Future<void> _analyze(PlatformFile file) async {
    setState(() {
      _analyzing = true;
      _fileName = file.name;
      _error = null;
    });
    try {
      final preview = await ApiService.analyzeDocument(file);
      if (!mounted) return;
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => VerifyDataScreen(initial: preview)));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  void _manualEntry() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const VerifyDataScreen()));

  // ── UI ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, ${auth.displayName}'),
        actions: const [LiveIndicator(), AppMenu()],
      ),
      body: RefreshIndicator(
        onRefresh: _apps.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Constrained(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _hero(context),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  MessageBanner(_error!),
                  const SizedBox(height: 16),
                ],
                ListenableBuilder(listenable: _apps, builder: (context, _) => _statsRow(context)),
                const SizedBox(height: 20),
                Row(children: [
                  const Expanded(
                    child: Text('Recent applications',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
                    child: const Text('See all'),
                  ),
                ]),
                const SizedBox(height: 6),
                ListenableBuilder(listenable: _apps, builder: (context, _) => _recent(context)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [AppTheme.brand, Color(0xFF0E7C66)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _analyzing ? _analyzingView() : _startView(),
      ),
    );
  }

  Widget _startView() {
    return Column(
      key: const ValueKey('start'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('New loan assessment',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(
          'Upload a salary slip or bank statement. We extract the numbers, '
          'you check them, and the risk score updates live.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), height: 1.45),
        ),
        const SizedBox(height: 18),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.white, foregroundColor: AppTheme.brand),
            onPressed: _chooseSource,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Upload document'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
            ),
            onPressed: _manualEntry,
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('Enter manually'),
          ),
        ]),
      ],
    );
  }

  Widget _analyzingView() {
    return Column(
      key: const ValueKey('busy'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [
          SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
          SizedBox(width: 14),
          Text('Analysing document…',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        Text(_fileName ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            minHeight: 6,
            color: Colors.white,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
          ),
        ),
        const SizedBox(height: 8),
        Text('Reading text, extracting figures and scoring risk',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
      ],
    );
  }

  Widget _statsRow(BuildContext context) {
    final s = _apps.stats;
    final byStatus = (s?['by_status'] as Map?) ?? {};
    final p = context.palette;
    final cards = [
      StatCard(label: 'Applications', value: '${s?['total'] ?? '–'}',
          icon: Icons.folder_copy_outlined, color: context.colors.primary),
      StatCard(label: 'Approved', value: '${byStatus['APPROVED'] ?? 0}',
          icon: Icons.check_circle_outline, color: p.success),
      StatCard(label: 'In review', value: '${byStatus['PENDING'] ?? 0}',
          icon: Icons.hourglass_top_rounded, color: p.warning),
    ];
    return Row(children: [
      for (var i = 0; i < cards.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(child: cards[i]),
      ],
    ]);
  }

  Widget _recent(BuildContext context) {
    if (_apps.loading && _apps.items.isEmpty) {
      return const Padding(
          padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    if (_apps.error != null && _apps.items.isEmpty) {
      return MessageBanner(_apps.error!, onRetry: _apps.load);
    }
    if (_apps.items.isEmpty) {
      return const EmptyState(
        icon: Icons.inbox_outlined,
        title: 'No applications yet',
        message: 'Your submitted applications and their live status will appear here.',
      );
    }
    return Column(children: [
      for (final a in _apps.items.take(5))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ApplicationTile(
            app: a,
            highlight: _apps.highlighted.contains(a.id),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ResultScreen(applicationId: a.id, initial: a))),
          ),
        ),
    ]);
  }
}
