import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:group_trip/app/app_dependencies.dart';
import 'package:group_trip/app/app_scope.dart';
import 'package:group_trip/core/theme/app_theme.dart';
import 'package:group_trip/core/theme/text_scaling_settings.dart';
import 'package:group_trip/core/theme/theme_mode_settings.dart';
import 'package:group_trip/core/widgets/app_shell.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/auth/presentation/auth_pages.dart';
import 'package:group_trip/features/consent/presentation/consent_page.dart';
import 'package:group_trip/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TravelApp extends StatefulWidget {
  const TravelApp({required this.deps, super.key});

  final AppDependencies deps;

  @override
  State<TravelApp> createState() => _TravelAppState();
}

class _TravelAppState extends State<TravelApp> {
  late ThemeModeSettings _themeSettings;
  late TextScalingSettings _textScaleSettings;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initSettings();
  }

  Future<void> _initSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _themeSettings = ThemeModeSettings(prefs);
    _textScaleSettings = TextScalingSettings(prefs);
    _themeSettings.addListener(_onSettingsChanged);
    _textScaleSettings.addListener(_onSettingsChanged);
    setState(() => _initialized = true);
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _themeSettings.removeListener(_onSettingsChanged);
    _textScaleSettings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AppScope(
      deps: widget.deps,
      child: _ThemeProvider(
        themeSettings: _themeSettings,
        textScaleSettings: _textScaleSettings,
        child: Builder(
          builder: (context) {
            final brightness = _themeSettings.resolveBrightness(context);
            final systemScale = MediaQuery.textScalerOf(context).scale(1.0);
            final effectiveScale = _textScaleSettings.computeScale(systemScale);

            return MaterialApp(
              title: AppStrings.appTitle,
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
              locale: const Locale('zh', 'TW'),
              supportedLocales: const [Locale('zh', 'TW')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(effectiveScale),
                  ),
                  child: child!,
                );
              },
              home: const RootPage(),
            );
          },
        ),
      ),
    );
  }
}

class _ThemeProvider extends InheritedWidget {
  const _ThemeProvider({
    required this.themeSettings,
    required this.textScaleSettings,
    required super.child,
  });

  final ThemeModeSettings themeSettings;
  final TextScalingSettings textScaleSettings;

  @override
  bool updateShouldNotify(_ThemeProvider oldWidget) {
    return themeSettings != oldWidget.themeSettings ||
        textScaleSettings != oldWidget.textScaleSettings;
  }
}

class RootPage extends StatelessWidget {
  const RootPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return StreamBuilder<UserAccount?>(
      stream: auth.watch(),
      initialData: auth.current,
      builder: (context, snapshot) {
        final account = snapshot.data;
        if (account == null) return const UnauthenticatedPage();
        if (!account.consentDecided) return const ConsentPage();
        return const AppShell();
      },
    );
  }
}
