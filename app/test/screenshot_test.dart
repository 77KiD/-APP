import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/core/theme/app_theme.dart';
import 'package:group_trip/core/widgets/app_shell.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    
    final fontLoader = FontLoader('Nunito')
      ..addFont(rootBundle.load('assets/fonts/Nunito-Bold.ttf'));
    await fontLoader.load();
    
    final dmSansLoader = FontLoader('DMSans')
      ..addFont(rootBundle.load('assets/fonts/DMSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/DMSans-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/DMSans-Bold.ttf'));
    await dmSansLoader.load();
    
    final notoLoader = FontLoader('NotoSansTC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansTC-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/NotoSansTC-Bold.ttf'));
    await notoLoader.load();
  });

  testWidgets('Screenshot: Light theme 100%', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const AppShell(
          currentTrip: '東京自由行 2026',
          chatUnreadCount: 2,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/light_100.png'),
    );
  });

  testWidgets('Screenshot: Light theme 150%', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: const AppShell(
            currentTrip: '東京自由行 2026',
            chatUnreadCount: 2,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/light_150.png'),
    );
  });

  testWidgets('Screenshot: Dark theme 100%', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const AppShell(
          currentTrip: '東京自由行 2026',
          chatUnreadCount: 2,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dark_100.png'),
    );
  });

  testWidgets('Screenshot: Dark theme 150%', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: const AppShell(
            currentTrip: '東京自由行 2026',
            chatUnreadCount: 2,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dark_150.png'),
    );
  });
}
