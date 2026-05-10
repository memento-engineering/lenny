import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable settings snapshot. Riverpod-managed via [SettingsNotifier].
@immutable
class Settings {
  const Settings({
    required this.theme,
    required this.notifications,
    required this.language,
  });

  factory Settings.initial() => const Settings(
        theme: ThemeMode.light,
        notifications: true,
        language: 'en',
      );

  final ThemeMode theme;
  final bool notifications;
  final String language;

  Settings copyWith({
    ThemeMode? theme,
    bool? notifications,
    String? language,
  }) =>
      Settings(
        theme: theme ?? this.theme,
        notifications: notifications ?? this.notifications,
        language: language ?? this.language,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Settings &&
          theme == other.theme &&
          notifications == other.notifications &&
          language == other.language;

  @override
  int get hashCode => Object.hash(theme, notifications, language);
}

class SettingsNotifier extends StateNotifier<Settings> {
  SettingsNotifier() : super(Settings.initial());

  void setTheme(ThemeMode mode) => state = state.copyWith(theme: mode);
  void setNotifications(bool enabled) =>
      state = state.copyWith(notifications: enabled);
  void setLanguage(String code) => state = state.copyWith(language: code);
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, Settings>(
  (ref) => SettingsNotifier(),
  name: 'settings',
);
