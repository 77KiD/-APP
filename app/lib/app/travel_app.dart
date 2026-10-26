import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:group_trip/app/app_dependencies.dart';
import 'package:group_trip/app/app_scope.dart';
import 'package:group_trip/core/theme/app_theme.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/auth/presentation/auth_pages.dart';
import 'package:group_trip/features/consent/presentation/consent_page.dart';
import 'package:group_trip/features/home/home_page.dart';
import 'package:group_trip/l10n/app_strings.dart';

class TravelApp extends StatelessWidget {
  const TravelApp({required this.deps, super.key});

  final AppDependencies deps;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      deps: deps,
      child: MaterialApp(
        title: AppStrings.appTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('zh', 'TW'),
        supportedLocales: const [Locale('zh', 'TW')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const RootPage(),
      ),
    );
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
        return const HomePage();
      },
    );
  }
}
