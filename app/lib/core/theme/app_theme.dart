import 'package:flutter/material.dart';
import 'package:group_trip/core/theme/app_colors.dart';

abstract final class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        secondary: AppColors.primary,
        onSecondary: AppColors.onPrimary,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        error: AppColors.error,
        onError: AppColors.onError,
      ),
      scaffoldBackgroundColor: AppColors.background,
    );
    final text = base.textTheme.apply(
      bodyColor: AppColors.onSurface,
      displayColor: AppColors.onSurface,
    );
    final buttonText = const TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
    return base.copyWith(
      textTheme: text,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.memberBackground,
          disabledForegroundColor: AppColors.memberForeground,
          minimumSize: const Size(48, 48),
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(48, 48),
          textStyle: buttonText,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        labelStyle: TextStyle(color: AppColors.onSurfaceVariant),
        helperStyle: TextStyle(color: AppColors.onSurfaceVariant),
        hintStyle: TextStyle(color: AppColors.onSurfaceVariant),
        border: OutlineInputBorder(),
      ),
      focusColor: AppColors.primary,
    );
  }
}
