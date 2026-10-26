import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/core/theme/app_colors.dart';

void main() {
  test('文字與角色標籤達到 WCAG AA', () {
    const pairs = [
      (AppColors.onSurface, AppColors.surface),
      (AppColors.onSurface, AppColors.background),
      (AppColors.onSurfaceVariant, AppColors.surface),
      (AppColors.onSurfaceVariant, AppColors.background),
      (AppColors.onPrimary, AppColors.primary),
      (AppColors.onError, AppColors.error),
      (AppColors.primary, AppColors.background),
      (AppColors.error, AppColors.surface),
      (AppColors.captainForeground, AppColors.captainBackground),
      (AppColors.viceForeground, AppColors.viceBackground),
      (AppColors.memberForeground, AppColors.memberBackground),
      (AppColors.staleLocation, AppColors.staleLocationBackground),
      (AppColors.staleLocation, AppColors.surface),
    ];
    for (final pair in pairs) {
      expect(
        _ratio(pair.$1, pair.$2),
        greaterThanOrEqualTo(4.5),
        reason: '${pair.$1} on ${pair.$2}',
      );
    }
  });
}

double _ratio(Color foreground, Color background) {
  final lighter = [
    foreground.computeLuminance(),
    background.computeLuminance(),
  ].reduce((a, b) => a > b ? a : b);
  final darker = [
    foreground.computeLuminance(),
    background.computeLuminance(),
  ].reduce((a, b) => a < b ? a : b);
  return (lighter + 0.05) / (darker + 0.05);
}
