import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/api.dart';
import '../state/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const List<({String code, String label})> _languages =
      <({String code, String label})>[
    (code: 'en', label: 'English'),
    (code: 'es', label: 'Español'),
    (code: 'fr', label: 'Français'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    Future<void> push() async {
      // Fire-and-forget update to demonstrate dio traffic when toggling.
      try {
        await ref.read(apiProvider).updateSettings(
              theme: settings.theme.name,
              notifications: settings.notifications,
              language: settings.language,
            );
      } on Object {
        // Best-effort; the FakeApiAdapter never errors here.
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: ListView(
        children: <Widget>[
          SwitchListTile(
            title: const Text('Dark Theme'),
            value: settings.theme == ThemeMode.dark,
            onChanged: (bool v) {
              notifier.setTheme(v ? ThemeMode.dark : ThemeMode.light);
              unawaited(push());
            },
          ),
          SwitchListTile(
            title: const Text('Notifications'),
            value: settings.notifications,
            onChanged: (bool v) {
              notifier.setNotifications(v);
              unawaited(push());
            },
          ),
          ListTile(
            title: const Text('Language'),
            trailing: DropdownButton<String>(
              value: settings.language,
              items: <DropdownMenuItem<String>>[
                for (final l in _languages)
                  DropdownMenuItem<String>(
                    value: l.code,
                    child: Text(l.label),
                  ),
              ],
              onChanged: (String? code) {
                if (code == null) return;
                notifier.setLanguage(code);
                unawaited(push());
              },
            ),
          ),
        ],
      ),
    );
  }
}

