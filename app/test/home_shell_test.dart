import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/app/app_dependencies.dart';
import 'package:group_trip/core/firebase/firebase_config.dart';
import 'package:group_trip/features/trip/domain/invite_link.dart';
import 'package:group_trip/features/trip/data/memory_trip_remote.dart';
import 'package:group_trip/features/home/presentation/decision_board_view.dart';
import 'package:group_trip/features/home/home_page.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/features/trip/domain/trip_repository.dart';
import 'package:group_trip/l10n/app_strings.dart';

import 'support/harness.dart';

void main() {
  Future<TestWorld> signedIn({
    bool firebase = false,
    _InviteReads? remote,
  }) async {
    final world = TestWorld(
      firebaseConfigured: firebase,
      remoteFactory: remote == null
          ? null
          : (database, user) {
              remote.databaseSource = database;
              remote.user = user;
              return remote;
            },
    );
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

  testWidgets('分享看板前重算，分享文字使用最新回程資料', (tester) async {
    tallView(tester);
    final world = await signedIn();
    final id = await createTrip(world);
    await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
    await tester.pumpAndSettle();
    await world.trips.updateExpectedReturnTime(
      tripId: id,
      proposed: DateTime.utc(2026, 11, 5, 9),
    );

    await tester.tap(find.byKey(const Key('share-board')));
    await tester.pumpAndSettle();

    expect(world.share.shared.single, contains('2026-11-05 17:00'));
    expect(
      world.share.shared.single,
      isNot(contains(AppStrings.boardSetReturn)),
    );
  });

  testWidgets('分享邀請前重算，使用最新旅程與邀請碼', (tester) async {
    tallView(tester);
    final world = await signedIn();
    final id = await createTrip(world);
    await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
    await tester.pumpAndSettle();
    world.clock.current = world.clock.current.add(const Duration(minutes: 1));
    world.database.clock = world.clock.current;
    final invite = await world.trips.issueInviteCode(id);

    await tester.tap(find.text(AppStrings.boardInviteFriends));
    await tester.pumpAndSettle();

    expect(
      world.share.shared.single,
      AppStrings.inviteShareText('京都自由行', invite.code),
    );
  });

  for (final invite in [false, true]) {
    testWidgets('分享${invite ? '邀請' : '看板'}讀取失敗，保留看板並可重試', (tester) async {
      tallView(tester);
      final world = await signedIn();
      await createTrip(world);
      final reads = _HomeReads(world.trips);
      await tester.pumpWidget(
        wrapPage(_withReads(world, reads), const HomePage()),
      );
      await tester.pumpAndSettle();
      reads.readTrip = (_) async => throw TripException('讀取失敗');

      await tester.tap(
        invite
            ? find.text(AppStrings.boardInviteFriends)
            : find.byKey(const Key('share-board')),
      );
      await tester.pumpAndSettle();

      expect(world.share.shared, isEmpty);
      expect(find.byKey(const Key('decision-board')), findsOneWidget);
      expect(find.text('無法更新看板，請重試後再分享'), findsOneWidget);
      reads.readTrip = null;
      await tester.tap(find.text('重試'));
      await tester.pumpAndSettle();
      expect(world.share.shared, hasLength(1));
    });
  }

  Future<void> returnHome(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.explore_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.home_outlined));
    await tester.pumpAndSettle();
  }

  for (final fail in [false, true]) {
    testWidgets('分享重讀被新載入取代，舊讀取${fail ? '失敗' : '成功'}不分享舊資料並提示重試', (
      tester,
    ) async {
      tallView(tester);
      final world = await signedIn();
      final id = await createTrip(world);
      final reads = _HomeReads(world.trips);
      await tester.pumpWidget(
        wrapPage(_withReads(world, reads), const HomePage()),
      );
      await tester.pumpAndSettle();
      final oldTrip = await world.trips.getTrip(id);
      final gate = Completer<Trip>();
      reads.readTrip = (_) => gate.future;
      await tester.tap(find.byKey(const Key('share-board')));
      await tester.pumpAndSettle();
      reads.readTrip = null;
      await world.trips.updateExpectedReturnTime(
        tripId: id,
        proposed: DateTime.utc(2026, 11, 5, 9),
      );
      await returnHome(tester);

      if (fail) {
        gate.completeError(TripException('舊分享失敗'));
      } else {
        gate.complete(oldTrip);
      }
      await tester.pumpAndSettle();

      expect(world.share.shared, isEmpty);
      expect(find.byKey(const Key('decision-board')), findsOneWidget);
      expect(find.text(AppStrings.boardSetReturn), findsNothing);
      expect(find.text(AppStrings.boardRefreshFailed), findsOneWidget);

      await tester.tap(find.text(AppStrings.boardRetry));
      await tester.pumpAndSettle();
      expect(world.share.shared.single, contains('2026-11-05 17:00'));
    });
  }

  /// 建立第二趟旅程並回傳選到的旅程與另一趟的標題。
  Future<({Trip selected, String otherTitle})> withSecondTrip(
    WidgetTester tester,
    TestWorld world,
  ) async {
    await world.trips.createTrip(
      const NewTripForm(
        title: '第二趟',
        startDate: '2026-11-01',
        endDate: '2026-11-05',
        timeZone: 'Asia/Taipei',
        returnDate: '',
        returnTime: '',
      ),
    );
    await returnHome(tester);
    final selected = tester
        .widget<DecisionBoardView>(find.byType(DecisionBoardView))
        .board
        .trip;
    return (
      selected: selected,
      otherTitle: selected.title == '第二趟' ? '京都自由行' : '第二趟',
    );
  }

  Future<void> switchToTrip(WidgetTester tester, String title) async {
    await tester.tap(find.text(title).first);
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
  }

  for (final fail in [false, true]) {
    testWidgets('切到別趟旅程後，舊分享${fail ? '失敗' : '完成'}不提示也不分享', (tester) async {
      tallView(tester);
      final world = await signedIn();
      await createTrip(world);
      final reads = _HomeReads(world.trips);
      await tester.pumpWidget(
        wrapPage(_withReads(world, reads), const HomePage()),
      );
      await tester.pumpAndSettle();
      final second = await withSecondTrip(tester, world);
      final gate = Completer<Trip>();
      reads.readTrip = (_) => gate.future;
      await tester.tap(find.byKey(const Key('share-board')));
      await tester.pumpAndSettle();
      reads.readTrip = null;

      await switchToTrip(tester, second.otherTitle);
      if (fail) {
        gate.completeError(TripException('舊分享失敗'));
      } else {
        gate.complete(second.selected);
      }
      await tester.pumpAndSettle();

      expect(world.share.shared, isEmpty);
      expect(find.text(AppStrings.boardRefreshFailed), findsNothing);
      expect(
        tester
            .widget<DecisionBoardView>(find.byType(DecisionBoardView))
            .board
            .trip
            .title,
        second.otherTitle,
      );
    });
  }

  testWidgets('切到別趟旅程後按舊提示的重試，不會分享另一趟', (tester) async {
    tallView(tester);
    final world = await signedIn();
    await createTrip(world);
    final reads = _HomeReads(world.trips);
    await tester.pumpWidget(
      wrapPage(_withReads(world, reads), const HomePage()),
    );
    await tester.pumpAndSettle();
    final second = await withSecondTrip(tester, world);
    reads.readTrip = (_) async => throw TripException('讀取失敗');
    await tester.tap(find.byKey(const Key('share-board')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final retry = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
    reads.readTrip = null;

    await switchToTrip(tester, second.otherTitle);
    retry.onPressed();
    await tester.pumpAndSettle();

    expect(world.share.shared, isEmpty);
  });

  testWidgets('清單載入中按分享，清單先回來也不取消分享或顯示失敗', (tester) async {
    tallView(tester);
    final world = await signedIn();
    final id = await createTrip(world);
    final reads = _HomeReads(world.trips);
    await tester.pumpWidget(
      wrapPage(_withReads(world, reads), const HomePage()),
    );
    await tester.pumpAndSettle();
    final trips = await world.trips.listMyTrips();
    final trip = await world.trips.getTrip(id);
    final listGate = Completer<List<Trip>>();
    final tripGate = Completer<Trip>();
    reads.readTrips = () => listGate.future;
    await returnHome(tester);
    reads.readTrip = (_) => tripGate.future;
    await tester.tap(find.byKey(const Key('share-board')));
    await tester.pump();

    listGate.complete(trips);
    await tester.pump();
    tripGate.complete(trip);
    await tester.pumpAndSettle();

    expect(world.share.shared, hasLength(1));
    expect(find.text(AppStrings.boardRefreshFailed), findsNothing);
  });

  testWidgets('略過背景載入後重驗失敗，看板仍更新成新資料，分享不含碼', (tester) async {
    tallView(tester);
    final remote = _InviteReads();
    final world = await signedIn(firebase: true, remote: remote);
    final id = await createTrip(world);
    final reads = _HomeReads(world.trips);
    await tester.pumpWidget(
      wrapPage(_withReads(world, reads), const HomePage()),
    );
    await tester.pumpAndSettle();
    final original = await world.trips.getTrip(id);
    final trips = await world.trips.listMyTrips();
    await world.trips.updateExpectedReturnTime(
      tripId: id,
      proposed: DateTime.utc(2026, 11, 5, 9),
    );
    final updated = await world.trips.getTrip(id);
    final listGate = Completer<List<Trip>>();
    final tripGate = Completer<Trip>();
    reads.readTrips = () => listGate.future;
    await returnHome(tester);
    reads.readTrip = (_) => tripGate.future;
    remote.fail = true;
    await tester.tap(find.byKey(const Key('share-board')));
    await tester.pump();

    listGate.complete(trips);
    await tester.pump();
    tripGate.complete(updated);
    await tester.pumpAndSettle();

    expect(world.share.shared.single, contains('2026-11-05 17:00'));
    expect(world.share.shared.single, isNot(contains(original.inviteCode)));
    final shown = tester
        .widget<DecisionBoardView>(find.byType(DecisionBoardView))
        .board;
    expect(shown.trip.expectedReturnAt, DateTime.utc(2026, 11, 5, 9));
    expect(shown.shareableInvite?.code, original.inviteCode);
  });

  testWidgets('清單回來後選中的旅程變了，舊分享取消且看板顯示新旅程', (tester) async {
    tallView(tester);
    final world = await signedIn();
    await createTrip(world);
    final reads = _HomeReads(world.trips);
    await tester.pumpWidget(
      wrapPage(_withReads(world, reads), const HomePage()),
    );
    await tester.pumpAndSettle();
    final second = await withSecondTrip(tester, world);
    final trips = await world.trips.listMyTrips();
    final remaining = [
      for (final trip in trips)
        if (trip.id != second.selected.id) trip,
    ];
    final listGate = Completer<List<Trip>>();
    final tripGate = Completer<Trip>();
    reads.readTrips = () => listGate.future;
    await returnHome(tester);
    reads.readTrip = (id) =>
        id == second.selected.id ? tripGate.future : world.trips.getTrip(id);
    await tester.tap(find.byKey(const Key('share-board')));
    await tester.pump();

    listGate.complete(remaining);
    await tester.pump();
    tripGate.complete(second.selected);
    await tester.pumpAndSettle();

    expect(world.share.shared, isEmpty);
    expect(find.text(AppStrings.boardRefreshFailed), findsNothing);
    expect(
      tester
          .widget<DecisionBoardView>(find.byType(DecisionBoardView))
          .board
          .trip
          .title,
      second.otherTitle,
    );
  });

  testWidgets('本機旅程還是舊的，伺服器已結束時不分享邀請碼', (tester) async {
    tallView(tester);
    final remote = _InviteReads();
    final world = await signedIn(firebase: true, remote: remote);
    final id = await createTrip(world);
    final trip = await world.trips.getTrip(id);
    await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
    await tester.pumpAndSettle();
    // 本機比遠端新時 getTrip 會回傳本機版本，看板讀到的仍是未結束的旅程。
    world.database.trips[id] = trip.copy(
      status: TripStatus.ended,
      updatedAt: trip.updatedAt.subtract(const Duration(minutes: 1)),
    );

    await tester.tap(find.text(AppStrings.boardInviteFriends));
    await tester.pumpAndSettle();
    expect(world.share.shared, isEmpty);
    expect(find.text(AppStrings.boardNoShareableInvite), findsWidgets);

    await tester.tap(find.byKey(const Key('share-board')));
    await tester.pumpAndSettle();
    expect(world.share.shared.single, isNot(contains(trip.inviteCode)));
    expect(world.share.shared.single, isNot(contains('https://')));
  });

  testWidgets('確認不存在的碼，回首頁後不再出現分享入口', (tester) async {
    tallView(tester);
    final remote = _InviteReads();
    final world = await signedIn(firebase: true, remote: remote);
    final id = await createTrip(world);
    final trip = await world.trips.getTrip(id);
    await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.boardShareInviteHint), findsOneWidget);
    world.database.invites.remove(trip.inviteCode);

    await tester.tap(find.text(AppStrings.boardInviteFriends));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.boardShareInviteHint), findsNothing);

    await returnHome(tester);
    expect(find.text(AppStrings.boardShareInviteHint), findsNothing);
  });

  testWidgets('連按分享只送出一次，也不顯示重試提示', (tester) async {
    tallView(tester);
    final world = await signedIn();
    final id = await createTrip(world);
    final reads = _HomeReads(world.trips);
    await tester.pumpWidget(
      wrapPage(_withReads(world, reads), const HomePage()),
    );
    await tester.pumpAndSettle();
    final oldTrip = await world.trips.getTrip(id);
    final gate = Completer<Trip>();
    reads.readTrip = (_) => gate.future;
    await tester.tap(find.byKey(const Key('share-board')));
    await tester.pumpAndSettle();
    reads.readTrip = null;
    await tester.tap(find.byKey(const Key('share-board')));
    await tester.pumpAndSettle();

    gate.complete(oldTrip);
    await tester.pumpAndSettle();

    expect(world.share.shared, hasLength(1));
    expect(find.text(AppStrings.boardRefreshFailed), findsNothing);
  });

  testWidgets('首頁移除後才按重試，不會丟例外也不分享', (tester) async {
    tallView(tester);
    final world = await signedIn();
    await createTrip(world);
    final reads = _HomeReads(world.trips);
    final deps = _withReads(world, reads);
    await tester.pumpWidget(wrapPage(deps, const HomePage()));
    await tester.pumpAndSettle();
    reads.readTrip = (_) async => throw TripException('讀取失敗');
    await tester.tap(find.byKey(const Key('share-board')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final retry = tester.widget<SnackBarAction>(find.byType(SnackBarAction));

    await tester.pumpWidget(wrapPage(deps, const Scaffold()));
    retry.onPressed();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(world.share.shared, isEmpty);
  });

  testWidgets('重驗暫時失敗時，畫面上的看板保留原本的分享入口', (tester) async {
    tallView(tester);
    final world = await signedIn();
    await createTrip(world);
    await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.boardShareInviteHint), findsOneWidget);
    world.connectivity.isOnline = false;

    await tester.tap(find.text(AppStrings.boardInviteFriends));
    await tester.pumpAndSettle();

    expect(world.share.shared, isEmpty);
    expect(find.text(AppStrings.boardRefreshFailed), findsOneWidget);
    expect(find.text(AppStrings.boardShareInviteHint), findsOneWidget);
    expect(find.text(AppStrings.boardNoShareableInvite), findsNothing);
  });

  testWidgets('重讀回傳不同旅程 ID 時不更新看板或分享', (tester) async {
    tallView(tester);
    final world = await signedIn();
    await createTrip(world);
    final reads = _HomeReads(world.trips);
    await tester.pumpWidget(
      wrapPage(_withReads(world, reads), const HomePage()),
    );
    await tester.pumpAndSettle();
    final original = tester
        .widget<DecisionBoardView>(find.byType(DecisionBoardView))
        .board;
    final otherId = await createTrip(world);
    final otherTrip = await world.trips.getTrip(otherId);
    reads.readTrip = (_) async => otherTrip;

    await tester.tap(find.byKey(const Key('share-board')));
    await tester.pumpAndSettle();

    expect(world.share.shared, isEmpty);
    expect(find.text(AppStrings.boardRefreshFailed), findsOneWidget);
    expect(
      tester.widget<DecisionBoardView>(find.byType(DecisionBoardView)).board,
      same(original),
    );
  });

  for (final fail in [false, true]) {
    for (final delayList in [false, true]) {
      testWidgets(
        '併發載入：舊${delayList ? '旅程清單' : '看板'}較晚${fail ? '失敗' : '完成'}不覆蓋最新看板',
        (tester) async {
          tallView(tester);
          final world = await signedIn();
          final id = await createTrip(world);
          final reads = _HomeReads(world.trips);
          await tester.pumpWidget(
            wrapPage(_withReads(world, reads), const HomePage()),
          );
          await tester.pumpAndSettle();
          final oldTrip = await world.trips.getTrip(id);
          final tripGate = Completer<Trip>();
          final listGate = Completer<List<Trip>>();
          if (delayList) {
            reads.readTrips = () => listGate.future;
          } else {
            reads.readTrip = (_) => tripGate.future;
          }
          await returnHome(tester);
          reads.readTrip = null;
          reads.readTrips = null;
          await world.trips.updateExpectedReturnTime(
            tripId: id,
            proposed: DateTime.utc(2026, 11, 5, 9),
          );
          await returnHome(tester);
          expect(find.text(AppStrings.boardSetReturn), findsNothing);

          if (delayList) {
            if (fail) {
              listGate.completeError(TripException('舊清單失敗'));
            } else {
              listGate.complete([]);
            }
          } else if (fail) {
            tripGate.completeError(TripException('舊看板失敗'));
          } else {
            tripGate.complete(oldTrip);
          }
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('decision-board')), findsOneWidget);
          expect(find.text(AppStrings.boardSetReturn), findsNothing);
          expect(find.text('舊清單失敗'), findsNothing);
          expect(find.text('舊旅程'), findsNothing);
          expect(
            tester
                .widget<DecisionBoardView>(find.byType(DecisionBoardView))
                .board
                .trip
                .expectedReturnAt,
            DateTime.utc(2026, 11, 5, 9),
          );
        },
      );
    }
  }

  for (final failure in ['disabled', 'missing', 'offline', 'error']) {
    testWidgets('分享前重新確認已確認的碼：$failure', (tester) async {
      tallView(tester);
      final remote = _InviteReads();
      final world = await signedIn(firebase: true, remote: remote);
      final id = await createTrip(world);
      final trip = await world.trips.getTrip(id);
      remote.reads = 0;
      await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
      await tester.pumpAndSettle();
      expect(remote.reads, 0, reason: '一般首頁不重查已確認的碼');
      final original = world.database.invites[trip.inviteCode]!;
      if (failure == 'disabled') {
        world.database.invites[original.code] = InviteRecord(
          code: original.code,
          tripId: id,
          createdBy: original.createdBy,
          createdAt: original.createdAt,
          expiresAt: original.expiresAt,
          active: false,
        );
      } else if (failure == 'missing') {
        world.database.invites.remove(original.code);
      } else if (failure == 'offline') {
        world.connectivity.isOnline = false;
      } else {
        remote.fail = true;
      }
      await tester.tap(find.text(AppStrings.boardInviteFriends));
      await tester.pumpAndSettle();
      expect(world.share.shared, isEmpty);
      if (failure == 'offline' || failure == 'error') {
        expect(find.text(AppStrings.boardRefreshFailed), findsOneWidget);
        remote.fail = false;
        world.connectivity.isOnline = true;
        await tester.tap(find.text(AppStrings.boardRetry));
        await tester.pumpAndSettle();
        expect(world.share.shared.single, contains(original.code));
        world.share.shared.clear();
        remote.fail = true;
        world.connectivity.isOnline = failure != 'offline';
      } else {
        expect(find.text(AppStrings.boardNoShareableInvite), findsWidgets);
        if (failure == 'disabled') {
          expect(
            (await world.trips.local.readInvite(original.code))!.active,
            isFalse,
          );
        }
      }
      await tester.tap(find.byKey(const Key('share-board')));
      await tester.pumpAndSettle();
      expect(
        world.share.shared.single,
        startsWith(AppStrings.boardShareTitle(trip.title)),
      );
      expect(world.share.shared.single, isNot(contains(original.code)));
      expect(world.share.shared.single, isNot(contains('https://')));
    });
  }

  for (final failure in ['disabled', 'offline', 'error']) {
    testWidgets('分享看板省略未通過重驗的碼與連結：$failure', (tester) async {
      tallView(tester);
      final remote = _InviteReads();
      final world = await signedIn(firebase: true, remote: remote);
      final id = await createTrip(world);
      final trip = await world.trips.getTrip(id);
      await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
      await tester.pumpAndSettle();
      if (failure == 'disabled') {
        final old = world.database.invites[trip.inviteCode]!;
        world.database.invites[old.code] = InviteRecord(
          code: old.code,
          tripId: id,
          createdBy: old.createdBy,
          createdAt: old.createdAt,
          expiresAt: old.expiresAt,
          active: false,
        );
      } else if (failure == 'offline') {
        world.connectivity.isOnline = false;
      } else {
        remote.fail = true;
      }
      await tester.tap(find.byKey(const Key('share-board')));
      await tester.pumpAndSettle();
      final text = world.share.shared.single;
      expect(text, startsWith(AppStrings.boardShareTitle(trip.title)));
      expect(text, contains(AppStrings.boardDates));
      expect(text, contains(AppStrings.boardMemberCount(1)));
      expect(text, isNot(contains(trip.inviteCode)));
      expect(text, isNot(contains('https://')));
    });
  }

  testWidgets('另有通過重驗的碼時仍可分享', (tester) async {
    tallView(tester);
    final remote = _InviteReads();
    final world = await signedIn(remote: remote);
    final id = await createTrip(world);
    final trip = await world.trips.getTrip(id);
    world.clock.current = world.clock.current.add(const Duration(minutes: 1));
    world.database.clock = world.clock.current;
    final newer = await world.trips.issueInviteCode(id);
    await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
    await tester.pumpAndSettle();
    world.database.invites.remove(newer.code);
    await tester.tap(find.text(AppStrings.boardInviteFriends));
    await tester.pumpAndSettle();
    expect(world.share.shared.single, contains(trip.inviteCode));
    expect(world.share.shared.single, isNot(contains(newer.code)));
  });

  testWidgets(
    'Firebase 首頁分享邀請包含連結',
    (tester) async {
      tallView(tester);
      final world = await signedIn(firebase: true);
      final id = await createTrip(world);
      final trip = await world.trips.getTrip(id);
      await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.boardInviteFriends));
      await tester.pumpAndSettle();
      expect(
        world.share.shared.single,
        contains(
          InviteLink.build(
            projectId: FirebaseConfig.projectId,
            code: trip.inviteCode,
          )!,
        ),
      );
    },
    // flutter test --dart-define=FIREBASE_PROJECT_ID=share-test
    skip: FirebaseConfig.projectId.isEmpty,
  );

  testWidgets('清單載入中分享仍會更新旅程清單', (tester) async {
    tallView(tester);
    final world = await signedIn();
    await createTrip(world);
    final reads = _HomeReads(world.trips);
    await tester.pumpWidget(
      wrapPage(_withReads(world, reads), const HomePage()),
    );
    await tester.pumpAndSettle();
    final trips = await world.trips.listMyTrips();
    final newTrip = await world.trips.createTrip(
      const NewTripForm(
        title: '新旅程',
        startDate: '2026-11-01',
        endDate: '2026-11-05',
        timeZone: 'Asia/Taipei',
        returnDate: '',
        returnTime: '',
      ),
    );
    expect(trips, hasLength(1));
    final gate = Completer<List<Trip>>();
    reads.readTrips = () => gate.future;
    await returnHome(tester);
    await tester.tap(find.byKey(const Key('share-board')));
    await tester.pumpAndSettle();
    gate.complete([newTrip]);
    await tester.pumpAndSettle();
    expect(find.text('新旅程'), findsWidgets);
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

AppDependencies _withReads(TestWorld world, TripRepository reads) {
  final deps = world.deps;
  return AppDependencies(
    auth: deps.auth,
    trips: reads,
    telemetry: deps.telemetry,
    clock: deps.clock,
    timeZone: deps.timeZone,
    disclosure: deps.disclosure,
    location: deps.location,
    connectivity: deps.connectivity,
    ids: deps.ids,
    firebaseConfigured: deps.firebaseConfigured,
    share: deps.share,
  );
}

/// 只控制首頁讀取的完成順序，其餘資料仍由既有 harness 提供。
class _HomeReads implements TripRepository {
  _HomeReads(this.delegate);
  final TripRepository delegate;
  Future<Trip> Function(String)? readTrip;
  Future<List<Trip>> Function()? readTrips;

  @override
  Future<Trip> getTrip(String id) => readTrip?.call(id) ?? delegate.getTrip(id);
  @override
  Future<List<Trip>> listMyTrips() =>
      readTrips?.call() ?? delegate.listMyTrips();
  @override
  Future<List<TripMember>> listMembers(String id) => delegate.listMembers(id);
  @override
  Future<List<ModificationRequest>> listRequests(String id) =>
      delegate.listRequests(id);
  @override
  Future<List<InviteRecord>> listInvites(String id) => delegate.listInvites(id);
  @override
  Future<({List<InviteRecord> invites, bool failed})> revalidateInvites(
    String id,
  ) => delegate.revalidateInvites(id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 模擬 Firestore：不能列出邀請碼，只能依已知碼逐筆讀取。
class _InviteReads extends MemoryTripRemote {
  _InviteReads()
    : super(database: MemoryTripDatabase(), currentUserId: () => '');
  late MemoryTripDatabase databaseSource;
  late String Function() user;
  bool fail = false;
  int reads = 0;
  @override
  MemoryTripDatabase get database => databaseSource;
  @override
  String Function() get currentUserId => user;
  @override
  Future<List<InviteRecord>> fetchInvites(String tripId) async => [];
  @override
  Future<InviteRecord?> fetchInvite(String code) async {
    if (database.invites.containsKey(code)) reads++;
    if (fail) throw TripException('讀取失敗');
    return super.fetchInvite(code);
  }
}
