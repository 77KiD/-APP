import 'package:flutter/material.dart';

/// 文字與底色的對比在 test/contrast_test.dart 檢查，目標是 WCAG AA。
abstract final class AppColors {
  static const background = Color(0xFFF7F5F2);
  static const surface = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFF1C1917);
  static const onSurfaceVariant = Color(0xFF3F3A36);
  static const primary = Color(0xFF123E40);
  static const onPrimary = Color(0xFFFFFFFF);
  static const error = Color(0xFF8E1B1B);
  static const onError = Color(0xFFFFFFFF);
  static const captainBackground = Color(0xFFD5E8E6);
  static const captainForeground = Color(0xFF0E3334);
  static const viceBackground = Color(0xFFF4E4CC);
  static const viceForeground = Color(0xFF5A3410);
  static const memberBackground = Color(0xFFE6E4E1);
  static const memberForeground = Color(0xFF292524);

  /// 「舊位置」用的灰色。這一版還沒有找人地圖，先把對比定下來。
  static const staleLocation = Color(0xFF374151);
  static const staleLocationBackground = Color(0xFFE5E7EB);
}
