import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/features/home/home_page.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/l10n/app_strings.dart';

import 'support/harness.dart';

void main() {
  Future<TestWorld> signedIn() async {
    final world = TestWorld();
    await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: DateTime(2026, 10, 26),
    );
    return world;
  }

  testWidgets('首頁有招呼語、旅程卡片，沒有聊天分頁', (tester) async {
    // 首頁多了決定看板，畫面拉高讓建立與加入按鈕也在畫面內。
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final world = await signedIn();
    await world.trips.createTrip(
      const NewTripForm(
        title: '京都自由行',
        startDate: '2026-11-01',
        endDate: '2026-11-05',
        timeZone: 'Asia/Taipei',
        returnDate: '',
        returnTime: '',
      ),
    );
    await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.greeting('小美')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('京都自由行，${AppStrings.statusPlanning}')),
      findsOneWidget,
    );
    expect(find.text('聊天'), findsNothing);
    expect(find.text(AppStrings.createTrip), findsOneWidget);
    expect(find.text(AppStrings.joinTrip), findsOneWidget);
    // 隱私與登出移到個人設定，不再放在首頁。
    expect(find.text(AppStrings.signOut), findsNothing);
  });

  testWidgets('首頁顯示決定看板，可以把看板與邀請碼分享到 LINE', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final world = await signedIn();
    final trip = await world.trips.createTrip(
      const NewTripForm(
        title: '京都自由行',
        startDate: '2026-11-01',
        endDate: '2026-11-05',
        timeZone: 'Asia/Taipei',
        returnDate: '',
        returnTime: '',
      ),
    );
    await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('decision-board')), findsOneWidget);
    expect(find.text(AppStrings.boardTodo), findsOneWidget);
    expect(find.text(AppStrings.boardSetReturn), findsOneWidget);

    await tester.tap(find.text(AppStrings.boardInviteFriends));
    await tester.pumpAndSettle();
    expect(world.share.shared.single, contains(trip.inviteCode));

    await tester.tap(find.byKey(const Key('share-board')));
    await tester.pumpAndSettle();
    expect(
      world.share.shared.last,
      startsWith(AppStrings.boardShareTitle('京都自由行')),
    );
  });

  Future<String> createTrip(TestWorld world) async {
    final trip = await world.trips.createTrip(
      const NewTripForm(
        title: '京都自由行',
        startDate: '2026-11-01',
        endDate: '2026-11-05',
        timeZone: 'Asia/Taipei',
        returnDate: '',
        returnTime: '',
      ),
    );
    return trip.id;
  }

  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('畫面載入後邀請碼過期，分享時不會送出舊碼（#60 F02）', (tester) async {
    tallView(tester);
    final world = await signedIn();
    await createTrip(world);
    await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.boardShareInviteHint), findsOneWidget);

    // 停在首頁超過一小時，碼已過期。
    world.clock.current = world.clock.current.add(const Duration(hours: 2));
    await tester.tap(find.text(AppStrings.boardInviteFriends));
    await tester.pumpAndSettle();

    expect(world.share.shared, isEmpty);
    expect(find.text(AppStrings.boardNoShareableInvite), findsWidgets);
  });

  testWidgets('在行程分頁改了回程，回首頁看板會更新（#60 F03）', (tester) async {
    tallView(tester);
    final world = await signedIn();
    final tripId = await createTrip(world);
    await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.boardSetReturn), findsOneWidget);

    await tester.tap(find.text('行程'));
    await tester.pumpAndSettle();
    await world.trips.updateExpectedReturnTime(
      tripId: tripId,
      proposed: DateTime.utc(2026, 11, 5, 9),
    );
    // 凸起的首頁按鈕只有圖示，沒有文字標籤。
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.boardSetReturn), findsNothing);
  });

  testWidgets('頭像進入個人設定，裡面有隱私說明與登出', (tester) async {
    final world = await signedIn();
    await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.settingsTitle), findsOneWidget);
    expect(find.text(AppStrings.locationDisclosureEntry), findsOneWidget);
    expect(find.text(AppStrings.dataInventoryEntry), findsOneWidget);
    expect(find.text(AppStrings.telemetrySettings), findsOneWidget);
    expect(find.text(AppStrings.signOut), findsOneWidget);
  });

  testWidgets('沒有旅程時，行程分頁顯示先建立或加入旅程', (tester) async {
    final world = await signedIn();
    await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.emptyTrips), findsOneWidget);
    await tester.tap(find.text('行程'));
    await tester.pumpAndSettle();
    expect(find.text('建立或加入旅程後，就能在這裡規劃行程'), findsOneWidget);
  });
}
