import 'package:flutter/material.dart';
import 'package:group_trip/core/theme/app_colors.dart';
import 'package:group_trip/core/theme/semantic_colors.dart';
import 'package:group_trip/core/theme/spacing.dart';

abstract final class AppTheme {
  static ThemeData light() {
    return _buildTheme(
      brightness: Brightness.light,
      semanticColors: SemanticColors.light,
      scaffoldBg: SemanticColors.light.bg,
    );
  }

  static ThemeData dark() {
    return _buildTheme(
      brightness: Brightness.dark,
      semanticColors: SemanticColors.dark,
      scaffoldBg: SemanticColors.dark.bg,
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required SemanticColors semanticColors,
    required Color scaffoldBg,
  }) {
    const headingFont = TextStyle(
      fontFamily: 'Nunito',
      fontFamilyFallback: ['NotoSansTC'],
      fontWeight: FontWeight.w700,
      height: 1.5,
    );
    const bodyFont = TextStyle(
      fontFamily: 'DMSans',
      fontFamilyFallback: ['NotoSansTC'],
      fontWeight: FontWeight.w400,
      height: 1.5,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: semanticColors.primary,
        onPrimary: semanticColors.onAccent,
        secondary: semanticColors.accent,
        onSecondary: semanticColors.onAccent,
        surface: semanticColors.surface,
        onSurface: semanticColors.text,
        error: semanticColors.red,
        onError: semanticColors.onAccent,
      ),
      scaffoldBackgroundColor: scaffoldBg,
      extensions: [semanticColors],
    );

    final textTheme = TextTheme(
      displayLarge: headingFont.copyWith(fontSize: 34),
      displayMedium: headingFont.copyWith(fontSize: 22),
      displaySmall: headingFont.copyWith(fontSize: 20),
      headlineLarge: headingFont.copyWith(fontSize: 20),
      headlineMedium: headingFont.copyWith(fontSize: 16),
      headlineSmall: headingFont.copyWith(fontSize: 15),
      bodyLarge: bodyFont.copyWith(fontSize: 16),
      bodyMedium: bodyFont.copyWith(fontSize: 15),
      bodySmall: bodyFont.copyWith(fontSize: 14),
      labelLarge: bodyFont.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      labelMedium: bodyFont.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      labelSmall: bodyFont.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
    ).apply(
      bodyColor: semanticColors.text,
      displayColor: semanticColors.text,
    );

    final buttonText = bodyFont.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w700,
    );

    return base.copyWith(
      textTheme: textTheme,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: semanticColors.accent,
          foregroundColor: semanticColors.onAccent,
          disabledBackgroundColor: AppColors.memberBackground,
          disabledForegroundColor: AppColors.memberForeground,
          minimumSize: const Size(48, 48),
          textStyle: buttonText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: semanticColors.primary,
          minimumSize: const Size(48, 48),
          textStyle: buttonText,
          side: BorderSide(color: semanticColors.line, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: TextStyle(color: semanticColors.muted),
        helperStyle: TextStyle(color: semanticColors.muted),
        hintStyle: TextStyle(color: semanticColors.dim),
        filled: true,
        fillColor: semanticColors.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide(color: semanticColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide(color: semanticColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide(color: semanticColors.primaryInk, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: BorderSide(color: semanticColors.red, width: 2),
        ),
      ),
      focusColor: semanticColors.primaryInk,
    );
  }
}
