import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/theme_service.dart';

/// Overflow menu shared by the home screen and dashboard.
class AppMenu extends StatelessWidget {
  const AppMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final theme = context.watch<ThemeService>();
    return PopupMenuButton<String>(
      tooltip: 'Account',
      icon: CircleAvatar(
        radius: 16,
        child: Text(auth.displayName.isNotEmpty ? auth.displayName[0].toUpperCase() : '?'),
      ),
      onSelected: (v) {
        if (v == 'theme') theme.toggleTheme();
        if (v == 'logout') auth.logout();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(auth.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${auth.userEmail ?? ''} · ${auth.isAdmin ? 'Bank officer' : 'Applicant'}',
                style: const TextStyle(fontSize: 12)),
          ]),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'theme',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(theme.isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            title: Text(theme.isDarkMode ? 'Light mode' : 'Dark mode'),
          ),
        ),
        const PopupMenuItem(
          value: 'logout',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded),
            title: Text('Sign out'),
          ),
        ),
      ],
    );
  }
}
