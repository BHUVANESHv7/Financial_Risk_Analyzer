import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _fadeIn(double start, Widget child) {
    final a = CurvedAnimation(parent: _c, curve: Interval(start, 1, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const features = [
      (Icons.document_scanner_outlined, 'Reads salary slips & statements', 'OCR + NLP extracts the numbers for you'),
      (Icons.speed_rounded, 'Live risk score', 'Watch the score change as you adjust values'),
      (Icons.bolt_rounded, 'Real-time decisions', 'Officers review instantly, you are notified live'),
    ];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B1E4B), AppTheme.brand, Color(0xFF0E7C66)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _fadeIn(0, Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 72,
                        height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Icon(Icons.analytics_rounded, size: 40, color: Colors.white),
                      ),
                    )),
                    const SizedBox(height: 28),
                    _fadeIn(0.1, const Text(
                      'AI Loan Risk\nAnalyzer',
                      style: TextStyle(
                        fontSize: 38,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    )),
                    const SizedBox(height: 12),
                    _fadeIn(0.2, Text(
                      'Upload a document, verify the numbers, and get an explainable '
                      'credit decision in seconds.',
                      style: TextStyle(fontSize: 15, height: 1.5,
                          color: Colors.white.withValues(alpha: 0.8)),
                    )),
                    const SizedBox(height: 32),
                    for (var i = 0; i < features.length; i++)
                      _fadeIn(0.3 + i * 0.1, Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(features[i].$1, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(features[i].$2, style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.w700)),
                              Text(features[i].$3, style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                            ]),
                          ),
                        ]),
                      )),
                    const SizedBox(height: 28),
                    _fadeIn(0.6, FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.brand,
                      ),
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                      child: const Text('Sign in'),
                    )),
                    const SizedBox(height: 12),
                    _fadeIn(0.65, OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                      ),
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                      child: const Text('Create an account'),
                    )),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
