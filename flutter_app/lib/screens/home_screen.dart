import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'verify_data_screen.dart';
import 'history_screen.dart';
import 'camera_screen.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/theme_service.dart';
import 'admin_dashboard.dart';
import 'login_screen.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  PlatformFile? _pickedFile;
  bool _isLoading = false;
  String? _errorMessage;
  bool _serverOnline = false;

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  Future<void> _checkServer() async {
    final online = await ApiService.checkHealth();
    if (mounted) setState(() => _serverOnline = online);
  }

  Future<void> _showSourcePicker() async {
    setState(() => _errorMessage = null);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const Text(
                  'Choose Document Source',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEBF5FF),
                    child: Icon(Icons.camera_alt_outlined,
                        color: Color(0xFF1A56DB)),
                  ),
                  title: const Text('Camera',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Take a photo now',
                      style: TextStyle(color: Colors.grey)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () async {
                    Navigator.pop(context);
                    final XFile? result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const CameraScreen()),
                    );
                    if (result != null) {
                      _handleCameraResult(result);
                    }
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFDE8E8),
                    child:
                        Icon(Icons.folder_outlined, color: Color(0xFFF98080)),
                  ),
                  title: const Text('Browse Files',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('JPG, PNG, PDF',
                      style: TextStyle(color: Colors.grey)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    Navigator.pop(context);
                    _pickFile();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleCameraResult(XFile image) async {
    try {
      final bytes = await image.readAsBytes();
      
      // Ensure the filename has a valid extension for the backend
      String fileName = image.name;
      if (!fileName.contains('.') || fileName.toLowerCase() == 'blob') {
        fileName = 'camera_capture_${DateTime.now().millisecondsSinceEpoch}.jpg';
      }

      setState(() {
        _pickedFile = PlatformFile(
          name: fileName,
          size: bytes.length,
          path: kIsWeb ? null : image.path,
          bytes: bytes,
        );
      });
      _analyzeRisk();
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Failed to process camera image: $e');
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      if (mounted) setState(() => _pickedFile = result.files.first);
    }
  }

  Future<void> _handleLogout() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _analyzeRisk() async {
    if (_pickedFile == null) {
      setState(() => _errorMessage = 'Please select a document first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      if (auth.token == null) throw Exception("Session expired. Please login again.");

      final result = await ApiService.analyzeLoan(_pickedFile!, auth.token!);
      if (!mounted) return;
      
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => VerifyDataScreen(
              initialResult: result,
            )),
      );
    } catch (e) {
      setState(
          () => _errorMessage = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    final authService = Provider.of<AuthService>(context);
    final isDark = themeService.isDarkMode;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Risk Analyzer'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => themeService.toggleTheme(),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => authService.isAdmin
                    ? const AdminDashboard()
                    : const HistoryScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(
                  authService.isAdmin ? Icons.admin_panel_settings : Icons.person,
                  color: const Color(0xFF1A56DB),
                ),
              ),
              accountName: Text(authService.isAdmin ? "Bank Officer" : "Applicant"),
              accountEmail: Text(authService.userEmail ?? ''),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFF1A56DB),
              ),
            ),
            if (authService.isAdmin)
              ListTile(
                leading: const Icon(Icons.dashboard_outlined),
                title: const Text('Admin Dashboard'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminDashboard()),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: Text(authService.isAdmin ? 'Admin Panel' : 'My History'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => authService.isAdmin
                        ? const AdminDashboard()
                        : const HistoryScreen(),
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
              title: Text(isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode'),
              onTap: () {
                themeService.toggleTheme();
              },
            ),
            const Spacer(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: _handleLogout,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Server status chip ──────────────────────────────
            _ServerStatusChip(online: _serverOnline, onRefresh: _checkServer),
            const SizedBox(height: 20),

            // ── Hero header ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A56DB), Color(0xFF0E9F6E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Loan Risk Assessment',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text(
                    'Upload a salary slip or bank statement. '
                    'Our AI will assess the applicant\'s risk in seconds.',
                    style: TextStyle(
                        color: Colors.white70, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Steps guide ──────────────────────────────────────
            const _StepsCard(),
            const SizedBox(height: 24),

            // ── File picker card ─────────────────────────────────
            if (!authService.isAdmin) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Upload Document',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      const Text('Supported formats: PDF, JPG, PNG',
                          style:
                              TextStyle(color: Color(0xFF374151), fontSize: 12)),
                      const SizedBox(height: 16),
  
                      // Drop zone
                      GestureDetector(
                        onTap: _showSourcePicker,
                        child: Container(
                          height: 130,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF9FAFB),
                            border: Border.all(
                              color: _pickedFile != null
                                  ? const Color(0xFF0E9F6E)
                                  : const Color(0xFFD1D5DB),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _pickedFile == null
                              ? const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.cloud_upload_outlined,
                                        size: 40, color: Color(0xFF4B5563)),
                                    SizedBox(height: 8),
                                    Text('Tap to choose a file',
                                        style: TextStyle(
                                            color: Color(0xFF374151),
                                            fontWeight: FontWeight.w500)),
                                    Text('PDF, JPG or PNG',
                                        style: TextStyle(
                                            color: Color(0xFF4B5563),
                                            fontSize: 12)),
                                  ],
                                )
                              : _FilePreviewTile(
                                  file: _pickedFile!,
                                  onRemove: () =>
                                      setState(() => _pickedFile = null),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
  
              // ── Error message ────────────────────────────────────
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDE8E8),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF98080)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFF9B1C1C), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMessage!,
                            style: const TextStyle(
                                color: Color(0xFF9B1C1C), fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
  
              // ── Analyse button ───────────────────────────────────
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _analyzeRisk,
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.analytics_outlined),
                            SizedBox(width: 8),
                            Text('Analyse Risk',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                ),
              ),
            ],
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ─────────────────────────────────────────────────────────────

class _ServerStatusChip extends StatelessWidget {
  final bool online;
  final VoidCallback onRefresh;
  const _ServerStatusChip({required this.online, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: online ? const Color(0xFF0E9F6E) : const Color(0xFFE02424),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          online ? 'Server online' : 'Server offline',
          style: TextStyle(
            fontSize: 12,
            color: online ? const Color(0xFF0E9F6E) : const Color(0xFFE02424),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: onRefresh,
          child: const Icon(Icons.refresh, size: 14, color: Color(0xFF374151)),
        ),
      ],
    );
  }
}

class _StepsCard extends StatelessWidget {
  const _StepsCard();

  @override
  Widget build(BuildContext context) {
    final steps = [
      ('1', 'Upload document', Icons.upload_file_outlined),
      ('2', 'AI reads & extracts data', Icons.document_scanner_outlined),
      ('3', 'ML predicts risk', Icons.psychology_outlined),
      ('4', 'View decision', Icons.verified_outlined),
    ];
    return Card(
      color: const Color(0xFFF9FAFB),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How it works',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF111827))),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: steps.map((s) => _StepItem(s.$1, s.$2, s.$3)).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  final String num;
  final String label;
  final IconData icon;
  const _StepItem(this.num, this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xFFEBF5FF),
            child: Icon(icon, color: const Color(0xFF1A56DB), size: 20),
          ),
          const SizedBox(height: 6),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10, 
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.grey[400] 
                    : const Color(0xFF111827)
              )),
        ],
      ),
    );
  }
}

class _FilePreviewTile extends StatelessWidget {
  final PlatformFile file;
  final VoidCallback onRemove;
  const _FilePreviewTile({required this.file, required this.onRemove});

  String get _size {
    final kb = (file.size / 1024).toStringAsFixed(1);
    return '$kb KB';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file,
              color: Color(0xFF1A56DB), size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(_size,
                    style: const TextStyle(
                        color: Color(0xFF374151), fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF4B5563)),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
