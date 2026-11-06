/// Light, dark, or whatever the system uses.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'appearance';

/// The person's choice, saved on this device. Follows the system until
/// they pick one.
class AppearanceNotifier extends StateNotifier<ThemeMode> {
  AppearanceNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = switch (prefs.getString(_key)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {}
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }
}

final appearanceProvider = StateNotifierProvider<AppearanceNotifier, ThemeMode>(
  (ref) => AppearanceNotifier(),
);

/// What each choice is called.
String appearanceLabel(ThemeMode m) => switch (m) {
      ThemeMode.system => '跟随系统',
      ThemeMode.light => '浅色',
      ThemeMode.dark => '深色',
    };
