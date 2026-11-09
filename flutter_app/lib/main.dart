import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/risk_result.dart';
import 'screens/admin_dashboard.dart';
import 'screens/home_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/result_screen.dart';
import 'services/auth_service.dart';
import 'services/realtime_service.dart';
import 'services/theme_service.dart';
import 'theme/app_theme.dart';
import 'utils/format.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProxyProvider<AuthService, RealtimeService>(
          create: (_) => RealtimeService(),
          update: (_, auth, rt) => rt!..updateToken(auth.token),
        ),
      ],
      child: const LoanRiskApp(),
    ),
  );
}

class LoanRiskApp extends StatelessWidget {
  const LoanRiskApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeService>();
    return MaterialApp(
      title: 'AI Loan Risk Analyzer',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      themeMode: theme.themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const AuthGate(),
    );
  }
}

/// Chooses the start screen from auth state and owns app-wide live notifications.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<LiveEvent>? _sub;
  bool? _wasAuthed;

  @override
  void initState() {
    super.initState();
    _sub = context.read<RealtimeService>().events.listen(_onEvent);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onEvent(LiveEvent e) {
    final auth = context.read<AuthService>();
    if (!e.isApplication || !auth.isAuthenticated) return;
    final app = RiskResult.fromJson(e.data);

    String? message;
    if (auth.isAdmin && e.type == 'application.created') {
      message = 'New application: ${app.applicantName} · ${inrCompact(app.loanAmount)} · '
          '${Tone.risk(context, app.riskLevel).label}';
    } else if (!auth.isAdmin && e.type == 'application.updated' && app.isReviewed) {
      message = 'Your ${inrCompact(app.loanAmount)} application is now '
          '${Tone.status(context, app.status).label.toLowerCase()}';
    }
    if (message == null) return;

    messengerKey.currentState?.showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.bolt_rounded, color: Colors.amber),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: 'View',
        onPressed: () => navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => ResultScreen(applicationId: app.id)),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    // On login/logout, drop pushed screens (login form, details…) so the
    // user lands on the right start page.
    if (_wasAuthed != null && _wasAuthed != auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.popUntil((r) => r.isFirst);
        messengerKey.currentState?.clearSnackBars();
      });
    }
    _wasAuthed = auth.isAuthenticated;

    if (!auth.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.isAuthenticated) return const LandingScreen();
    return auth.isAdmin ? const AdminDashboard() : const HomeScreen();
  }
}
