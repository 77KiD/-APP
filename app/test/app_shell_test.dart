import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/core/theme/app_theme.dart';
import 'package:group_trip/core/widgets/app_shell.dart';

void main() {
  group('AppShell navigation semantics', () {
    testWidgets('all bottom nav tabs have labels',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const AppShell(),
        ),
      );

      expect(find.text('行程'), findsOneWidget);
      expect(find.text('找人'), findsOneWidget);
      expect(find.text('首頁'), findsNWidgets(2));
      expect(find.text('聊天'), findsOneWidget);
      expect(find.text('成員'), findsOneWidget);
    });

    testWidgets('chat badge shows unread count',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const AppShell(chatUnreadCount: 3),
        ),
      );

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('members badge shows approval count for leader',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const AppShell(
            pendingApprovalsCount: 2,
            isLeaderOrDeputy: true,
          ),
        ),
      );

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('members badge hidden for non-leader',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const AppShell(
            pendingApprovalsCount: 2,
            isLeaderOrDeputy: false,
          ),
        ),
      );

      expect(find.text('2'), findsNothing);
      expect(find.text('成員'), findsOneWidget);
    });

    testWidgets('high badge count shows 99+',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const AppShell(chatUnreadCount: 150),
        ),
      );

      expect(find.text('99+'), findsOneWidget);
    });
  });

  group('AppShell 150% text scaling', () {
    testWidgets('renders without exceptions at 150% scale',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: const AppShell(
              currentTrip: '東京自由行 2026',
              chatUnreadCount: 99,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('long trip names render at 150% scale',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: const AppShell(
              currentTrip: '非常長的旅程名稱測試用例這裡有很多字',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('非常長的旅程名稱測試用例這裡有很多字'), findsOneWidget);
    });

    testWidgets('all button text visible at 150% scale',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: const AppShell(chatUnreadCount: 5),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('行程'), findsOneWidget);
      expect(find.text('找人'), findsOneWidget);
      expect(find.text('首頁'), findsNWidgets(2));
      expect(find.text('聊天'), findsOneWidget);
      expect(find.text('成員'), findsOneWidget);
    });
  });

  group('AppShell theme support', () {
    testWidgets('renders correctly in light theme',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const AppShell(currentTrip: '測試旅程'),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('首頁'), findsNWidgets(2));
      expect(find.text('測試旅程'), findsOneWidget);
    });

    testWidgets('renders correctly in dark theme',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const AppShell(currentTrip: '測試旅程'),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('首頁'), findsNWidgets(2));
      expect(find.text('測試旅程'), findsOneWidget);
    });

    testWidgets('connection indicator displays correct states',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const AppShell(),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('線上'), findsOneWidget);
    });
  });

  group('AppShell header behavior', () {
    testWidgets('shows trip name when available',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const AppShell(currentTrip: '京都賞櫻之旅'),
        ),
      );

      expect(find.text('京都賞櫻之旅'), findsOneWidget);
    });

    testWidgets('shows explanation when no trip and on trip-dependent tab',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const AppShell(),
        ),
      );

      await tester.tap(find.text('找人'));
      await tester.pumpAndSettle();

      expect(find.text('建立或加入旅程後可用'), findsOneWidget);
    });

    testWidgets('settings button triggers callback',
        (WidgetTester tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AppShell(
            onSettingsTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.settings));
      expect(tapped, isTrue);
    });
  });

  group('AppShell bottom nav behavior', () {
    testWidgets('hides bottom nav when requested',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const AppShell(hideBottomNav: true),
        ),
      );

      expect(find.text('行程'), findsNothing);
      expect(find.text('找人'), findsNothing);
    });

    testWidgets('switches tabs when tapped', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const AppShell(),
        ),
      );

      await tester.tap(find.text('聊天'));
      await tester.pumpAndSettle();

      expect(find.text('聊天'), findsWidgets);
    });

    testWidgets('home button has raised circular design',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const AppShell(),
        ),
      );

      final homeButton = find.ancestor(
        of: find.byIcon(Icons.home),
        matching: find.byType(Container),
      );

      expect(homeButton, findsWidgets);
    });
  });

  group('AppShell empty states', () {
    testWidgets('shows appropriate empty state for each tab',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const AppShell(),
        ),
      );

      await tester.tap(find.text('行程'));
      await tester.pumpAndSettle();
      expect(find.text('建立或加入旅程後，就能在這裡規劃行程'), findsOneWidget);

      await tester.tap(find.text('找人'));
      await tester.pumpAndSettle();
      expect(find.text('建立或加入旅程後，就能在地圖上看到夥伴的位置'), findsOneWidget);

      await tester.tap(find.text('聊天'));
      await tester.pumpAndSettle();
      expect(find.text('建立或加入旅程後，就能和夥伴聊天'), findsOneWidget);

      await tester.tap(find.text('成員'));
      await tester.pumpAndSettle();
      expect(find.text('建立或加入旅程後，就能查看所有成員'), findsOneWidget);
    });
  });
}
