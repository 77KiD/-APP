import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TextScaleOverride {
  none(1.0),
  medium(1.15),
  large(1.30),
  extraLarge(1.50);

  const TextScaleOverride(this.scale);
  final double scale;

  static TextScaleOverride fromString(String? value) {
    switch (value) {
      case 'medium':
        return TextScaleOverride.medium;
      case 'large':
        return TextScaleOverride.large;
      case 'extraLarge':
        return TextScaleOverride.extraLarge;
      default:
        return TextScaleOverride.none;
    }
  }
}

class TextScalingSettings extends ChangeNotifier {
  TextScalingSettings(this._prefs) {
    _override = TextScaleOverride.fromString(_prefs.getString(_key));
  }

  static const _key = 'text_scale_override';
  final SharedPreferences _prefs;
  TextScaleOverride _override = TextScaleOverride.none;

  TextScaleOverride get override => _override;

  Future<void> setOverride(TextScaleOverride override) async {
    if (_override == override) return;
    _override = override;
    await _prefs.setString(_key, override.name);
    notifyListeners();
  }

  double computeScale(double systemScale) {
    if (_override == TextScaleOverride.none) {
      return systemScale;
    }
    return _override.scale;
  }
}
