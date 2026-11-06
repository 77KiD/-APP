import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/app/app_dependencies.dart';
import 'package:group_trip/features/home/presentation/decision_board_view.dart';
import 'package:group_trip/features/home/home_page.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/features/trip/domain/trip_repository.dart';
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
    testWidgets('分享重讀被新載入取代，舊讀取${fail ? '失敗' : '成功'}不分享或顯示過時提示', (
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
      expect(find.text(AppStrings.boardRefreshFailed), findsNothing);
    });
  }

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
