import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  auto,
  system,
  light,
  dark;

  static AppThemeMode fromString(String? value) {
    switch (value) {
      case 'auto':
        return AppThemeMode.auto;
      case 'system':
        return AppThemeMode.system;
      case 'light':
        return AppThemeMode.light;
      case 'dark':
        return AppThemeMode.dark;
      default:
        return AppThemeMode.auto;
    }
  }
}

class ThemeModeSettings extends ChangeNotifier {
  ThemeModeSettings(this._prefs) {
    _mode = AppThemeMode.fromString(_prefs.getString(_key));
    _startTimer();
  }

  static const _key = 'theme_mode';
  final SharedPreferences _prefs;
  AppThemeMode _mode = AppThemeMode.auto;
  DateTime? _lastCheck;

  AppThemeMode get mode => _mode;

  Future<void> setMode(AppThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    await _prefs.setString(_key, mode.name);
    notifyListeners();
  }

  Brightness resolveBrightness(BuildContext context) {
    switch (_mode) {
      case AppThemeMode.light:
        return Brightness.light;
      case AppThemeMode.dark:
        return Brightness.dark;
      case AppThemeMode.system:
        return MediaQuery.platformBrightnessOf(context);
      case AppThemeMode.auto:
        final now = DateTime.now();
        final hour = now.hour;
        return (hour >= 6 && hour < 18) ? Brightness.light : Brightness.dark;
    }
  }

  void _startTimer() {
    Future.delayed(const Duration(minutes: 1), () {
      final now = DateTime.now();
      if (_lastCheck == null ||
          now.difference(_lastCheck!).inMinutes >= 1) {
        _lastCheck = now;
        if (_mode == AppThemeMode.auto) {
          notifyListeners();
        }
      }
      _startTimer();
    });
  }
}

abstract final class AppSpacing {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 24;
  static const double s6 = 32;
}

abstract final class AppRadii {
  static const double card = 18;
  static const double button = 14;
  static const double input = 14;
  static const double sheet = 26;
  static const double tag = 8;
}

abstract final class AppDurations {
  static const fast = Duration(milliseconds: 120);
  static const mid = Duration(milliseconds: 220);
  static const standard = Duration(milliseconds: 300);
  static const sheet = Duration(milliseconds: 260);
}
