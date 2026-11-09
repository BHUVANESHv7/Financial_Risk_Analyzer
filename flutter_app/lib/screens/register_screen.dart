import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _invite = TextEditingController();
  String _role = 'APPLICANT';
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _invite]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _error = null);
    final auth = context.read<AuthService>();
    try {
      await auth.register(
        email: _email.text,
        password: _password.text,
        fullName: _name.text.trim(),
        role: _role,
        inviteCode: _role == 'ADMIN' ? _invite.text.trim() : null,
      );
      // Sign straight in — AuthGate then opens the right home screen.
      await auth.login(email: _email.text, password: _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthService>().isLoading;
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Create account',
                      style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 20),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'APPLICANT',
                          icon: Icon(Icons.person_outline),
                          label: Text('Applicant')),
                      ButtonSegment(
                          value: 'ADMIN',
                          icon: Icon(Icons.account_balance_outlined),
                          label: Text('Bank officer')),
                    ],
                    selected: {_role},
                    onSelectionChanged: (s) => setState(() => _role = s.first),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                        labelText: 'Full name', prefixIcon: Icon(Icons.badge_outlined)),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                        labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                    validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()))
                        ? 'Enter a valid email'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Password',
                        helperText: 'At least 6 characters',
                        prefixIcon: Icon(Icons.lock_outline)),
                    validator: (v) => (v == null || v.length < 6) ? 'Use at least 6 characters' : null,
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: _role == 'ADMIN'
                        ? Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: TextFormField(
                              controller: _invite,
                              decoration: const InputDecoration(
                                labelText: 'Officer invite code',
                                helperText: 'Provided by your bank administrator',
                                prefixIcon: Icon(Icons.key_outlined),
                              ),
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty) ? 'Invite code is required' : null,
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) ...[MessageBanner(_error!), const SizedBox(height: 14)],
                  FilledButton(
                    onPressed: busy ? null : _submit,
                    child: busy
                        ? const SizedBox(
                            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('Create account'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pushReplacement(
                        context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                    child: const Text('Already have an account? Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
