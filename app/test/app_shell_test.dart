import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/core/theme/app_theme.dart';
import 'package:group_trip/core/widgets/app_shell.dart';
import 'package:group_trip/l10n/app_strings.dart';

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
      expect(find.text('聊天'), findsNothing);
      expect(find.text('成員'), findsOneWidget);
    });

    testWidgets('聊天分頁已移除（ADR 0011）',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const AppShell(),
        ),
      );

      expect(BottomNavTab.values.map((tab) => tab.label), isNot(contains('聊天')));
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
    });

    group('下排保留原本的通訊位置', () {
      Future<void> pumpShell(
        WidgetTester tester,
        Size size, {
        double textScale = 1,
      }) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const AppShell(),
          ),
        );
        await tester.pump();
      }

      final slot = find.byKey(const Key('reserved-nav-slot'));

      for (final (size, scale) in [
        (const Size(320, 640), 1.0),
        (const Size(320, 640), 2.0),
        (const Size(412, 915), 1.0),
        (const Size(412, 915), 1.5),
        (const Size(800, 1000), 1.0),
      ]) {
        testWidgets('首頁在正中間：${size.width.toInt()} 寬，文字 $scale 倍', (
          tester,
        ) async {
          await pumpShell(tester, size, textScale: scale);

          expect(
            tester.getCenter(find.byIcon(Icons.home)).dx,
            closeTo(size.width / 2, 0.5),
          );
        });
      }

      testWidgets('順序是行程、找人、首頁、保留格、成員', (tester) async {
        await pumpShell(tester, const Size(412, 915));

        final centers = [
          find.byIcon(Icons.route_outlined),
          find.byIcon(Icons.explore_outlined),
          find.byIcon(Icons.home),
          slot,
          find.byIcon(Icons.people_outline),
        ].map((finder) => tester.getCenter(finder).dx).toList();

        expect(centers, orderedEquals([...centers]..sort()));
        // 五格等寬：相鄰兩格的間距都一樣。
        final gap = centers[1] - centers[0];
        for (var i = 2; i < centers.length; i++) {
          expect(centers[i] - centers[i - 1], closeTo(gap, 0.5));
        }
      });

      testWidgets('保留格顯示即將推出，比一般分頁淡，按了也不會切換分頁', (tester) async {
        await pumpShell(tester, const Size(412, 915));

        final label = find.descendant(
          of: slot,
          matching: find.text(AppStrings.navComingSoon),
        );
        final icon = find.descendant(
          of: slot,
          matching: find.byIcon(Icons.hourglass_empty),
        );
        expect(label, findsOneWidget);
        expect(icon, findsOneWidget);
        expect(
          find.descendant(of: slot, matching: find.byType(InkWell)),
          findsNothing,
        );
        expect(BottomNavTab.values, hasLength(4));

        final normal = tester.widget<Icon>(find.byIcon(Icons.people_outline));
        final reserved = tester.widget<Icon>(icon);
        expect(reserved.color!.a, lessThan(normal.color!.a));

        await tester.tapAt(tester.getCenter(slot));
        await tester.pump();
        expect(find.text('首頁'), findsNWidgets(2));
      });

      testWidgets('輔助技術念出即將推出，而且標示為不能使用', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpShell(tester, const Size(412, 915));

        final data = tester.getSemantics(slot).getSemanticsData();
        expect(data.label, AppStrings.navComingSoon);
        expect(data.flagsCollection.isEnabled, Tristate.isFalse);
        expect(data.hasAction(SemanticsAction.tap), isFalse);
        semantics.dispose();
      });
    });

    group('點下排時，圖示與文字位置不動', () {
      Finder tabIcon(BottomNavTab tab, BottomNavTab selected) =>
          find.byIcon(tab == selected ? tab.selectedIcon : tab.icon);

      // 分頁標題和內容也可能用同樣的文字，下排排在最後。
      Finder tabLabel(BottomNavTab tab) => find.text(tab.label).last;

      final slot = find.byKey(const Key('reserved-nav-slot'));
      // 保留格往上第一個 Container 就是整條下排。
      final navBar = find
          .ancestor(of: slot, matching: find.byType(Container))
          .first;

      Map<String, Offset> positions(
        WidgetTester tester,
        BottomNavTab selected,
      ) => {
        for (final tab in BottomNavTab.values) ...{
          'icon ${tab.name}': tester.getCenter(tabIcon(tab, selected)),
          if (tab != BottomNavTab.home)
            'label ${tab.name}': tester.getCenter(tabLabel(tab)),
        },
        'icon 即將推出': tester.getCenter(
          find.descendant(
            of: slot,
            matching: find.byIcon(Icons.hourglass_empty),
          ),
        ),
        'label 即將推出': tester.getCenter(
          find.descendant(
            of: slot,
            matching: find.text(AppStrings.navComingSoon),
          ),
        ),
        // 上下緣都不動，高度才算沒變。
        'nav 左上': tester.getTopLeft(navBar),
        'nav 右下': tester.getBottomRight(navBar),
      };

      for (final (size, scale) in [
        (const Size(320, 640), 1.0),
        (const Size(320, 640), 2.0),
        (const Size(412, 915), 1.0),
        (const Size(412, 915), 1.5),
        (const Size(800, 1000), 1.0),
      ]) {
        testWidgets('${size.width.toInt()} 寬，文字 $scale 倍', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const AppShell(currentTrip: '東京自由行'),
            ),
          );
          await tester.pumpAndSettle();
          final start = positions(tester, BottomNavTab.home);

          for (final tab in [
            BottomNavTab.itinerary,
            BottomNavTab.find,
            BottomNavTab.members,
            BottomNavTab.home,
          ]) {
            await tester.tap(
              find.ancestor(
                of: tab == BottomNavTab.home
                    ? find.byIcon(tab.icon).last
                    : tabLabel(tab),
                matching: find.byType(InkWell),
              ),
            );
            await tester.pumpAndSettle();

            final now = positions(tester, tab);
            for (final key in start.keys) {
              expect(
                (now[key]! - start[key]!).distance,
                lessThan(0.5),
                reason: '選到 ${tab.name} 時，$key 移動了：'
                    '${start[key]} → ${now[key]}',
              );
            }
          }
        });
      }

      testWidgets('切換分頁後，即將推出格仍然不能使用', (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.light(), home: const AppShell()),
        );
        await tester.pumpAndSettle();

        for (final tab in [
          BottomNavTab.itinerary,
          BottomNavTab.find,
          BottomNavTab.members,
        ]) {
          await tester.tap(tabLabel(tab));
          await tester.pumpAndSettle();

          final data = tester.getSemantics(slot).getSemanticsData();
          expect(data.label, AppStrings.navComingSoon, reason: tab.name);
          expect(
            data.flagsCollection.isEnabled,
            Tristate.isFalse,
            reason: tab.name,
          );
          expect(data.hasAction(SemanticsAction.tap), isFalse, reason: tab.name);

          // 按保留格不會換到別的分頁：選到的圖示還在。
          await tester.tapAt(tester.getCenter(slot));
          await tester.pumpAndSettle();
          expect(find.byIcon(tab.selectedIcon), findsOneWidget, reason: tab.name);
        }
        semantics.dispose();
      });

      testWidgets('選到的分頁，底色在圖示正中間', (tester) async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.light(), home: const AppShell()),
        );
        await tester.tap(find.text(BottomNavTab.itinerary.label).last);
        await tester.pumpAndSettle();

        final icon = find.byIcon(BottomNavTab.itinerary.selectedIcon);
        final pill = find.byKey(const Key('nav-selected-pill'));
        expect(pill, findsOneWidget);
        expect(
          (tester.getCenter(pill) - tester.getCenter(icon)).distance,
          lessThan(0.5),
        );
      });
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
          home: const AppShell(
            pendingApprovalsCount: 150,
            isLeaderOrDeputy: true,
          ),
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
              pendingApprovalsCount: 99,
              isLeaderOrDeputy: true,
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
            child: const AppShell(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('行程'), findsOneWidget);
      expect(find.text('找人'), findsOneWidget);
      expect(find.text('首頁'), findsNWidgets(2));
      expect(find.text('聊天'), findsNothing);
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

      await tester.tap(find.text('成員'));
      await tester.pumpAndSettle();

      expect(find.text('成員'), findsWidgets);
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

  group('AppShell body and status', () {
    testWidgets('bodyBuilder 提供分頁內容，回傳 null 時用預設畫面',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: AppShell(
            bodyBuilder: (context, tab) =>
                tab == BottomNavTab.home ? const Text('自訂首頁') : null,
          ),
        ),
      );

      expect(find.text('自訂首頁'), findsOneWidget);
      await tester.tap(find.text('行程'));
      await tester.pumpAndSettle();
      expect(find.text('建立或加入旅程後，就能在這裡規劃行程'), findsOneWidget);
    });

    testWidgets('離線時右上角顯示離線', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const AppShell(connectionStatus: ConnectionStatus.offline),
        ),
      );

      expect(find.text('離線'), findsOneWidget);
      expect(find.text('線上'), findsNothing);
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

      await tester.tap(find.text('成員'));
      await tester.pumpAndSettle();
      expect(find.text('建立或加入旅程後，就能查看所有成員'), findsOneWidget);
    });
  });
}
