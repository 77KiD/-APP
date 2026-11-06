import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/app/travel_app.dart';
import 'package:group_trip/core/persistence/key_value_document_store.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/features/home/home_page.dart';
import 'package:group_trip/features/trip/domain/invite_link.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/features/trip/presentation/trip_detail_page.dart';
import 'package:group_trip/l10n/app_strings.dart';

import 'support/harness.dart';

void main() {
  group('InviteLink（ADR 0012 第 3 點）', () {
    test('有專案才產生網址，並正規化邀請碼', () {
      expect(
        InviteLink.build(projectId: 'peers-demo', code: 'ab cd1234'),
        'https://peers-demo.web.app/j/ABCD1234',
      );
      expect(InviteLink.build(projectId: '', code: 'ABCD1234'), isNull);
    });

    test('從路徑或 hash 路由讀出邀請碼，格式不對就忽略', () {
      expect(
        InviteLink.parse(Uri.parse('https://x.web.app/j/abcd1234')),
        'ABCD1234',
      );
      expect(
        InviteLink.parse(Uri.parse('https://x.web.app/#/j/ABCD12345')),
        'ABCD12345',
      );
      expect(InviteLink.parse(Uri.parse('https://x.web.app/j/AB-12')), isNull);
      expect(InviteLink.parse(Uri.parse('https://x.web.app/')), isNull);
      expect(InviteLink.parse(null), isNull);
    });
  });

  group('網頁訪客註冊', () {
    test('不需要 email 與密碼，13 歲門檻照常', () async {
      final world = TestWorld();
      final kid = await world.auth.signUpGuest(
        displayName: '小朋友',
        birthday: '2016-04-01',
        birthdayConsent: true,
        today: DateTime(2026, 10, 26),
      );
      expect(kid.failure?.message, AppStrings.under13);
      expect(world.auth.current, isNull);

      final noConsent = await world.auth.signUpGuest(
        displayName: '凱文',
        birthday: '2000-04-01',
        birthdayConsent: false,
        today: DateTime(2026, 10, 26),
      );
      expect(noConsent.failure, isNotNull);

      final guest = await world.auth.signUpGuest(
        displayName: '凱文',
        birthday: '2000-04-01',
        birthdayConsent: true,
        today: DateTime(2026, 10, 26),
      );
      expect(guest.failure, isNull);
      expect(world.auth.current?.isGuest, isTrue);
      expect(world.auth.current?.displayName, '凱文');
    });

    testWidgets('網頁版未登入時先顯示訪客加入，可以改用 email 登入', (tester) async {
      final world = TestWorld(isWeb: true);
      await tester.pumpWidget(TravelApp(deps: world.deps));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.guestTitle), findsWidgets);
      await tester.tap(find.text(AppStrings.guestHasAccount));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.signInTitle), findsWidgets);
    });

    testWidgets('App 版未登入時仍是 email 登入', (tester) async {
      final world = TestWorld();
      await tester.pumpWidget(TravelApp(deps: world.deps));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.guestTitle), findsNothing);
      expect(find.text(AppStrings.signInTitle), findsWidgets);
    });
  });

  group('網頁版首頁', () {
    Future<TestWorld> signedIn({String? inviteCode}) async {
      final world = TestWorld(isWeb: true, initialInviteCode: inviteCode);
      await world.auth.signUpGuest(
        displayName: '凱文',
        birthday: '2000-04-01',
        birthdayConsent: true,
        today: DateTime(2026, 10, 26),
      );
      return world;
    }

    testWidgets('不能建立旅程，只能加入；找人分頁說明要用 App', (tester) async {
      final world = await signedIn();
      await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.createTrip), findsNothing);
      expect(find.text(AppStrings.webCreateInApp), findsOneWidget);
      expect(find.text(AppStrings.joinTrip), findsOneWidget);

      await tester.tap(find.text('找人'));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.webFindInApp), findsOneWidget);
    });

    testWidgets('從邀請連結打開時，直接到加入頁並填好邀請碼', (tester) async {
      final world = await signedIn(inviteCode: 'ABCD1234');
      await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.joinTitle), findsWidgets);
      final field = tester.widget<TextField>(
        labeledField(AppStrings.inviteCodeField),
      );
      expect(field.controller?.text, 'ABCD1234');
    });
  });

  group('網頁版旅程頁（ADR 0012 第 2 點）', () {
    /// 自己是指定角色的九人旅程，另有一筆待審核的回程申請。
    Future<({TestWorld world, Trip trip, String approve})> tripAs(
      MemberRole role, {
      required bool web,
    }) async {
      final world = TestWorld(isWeb: web);
      await world.auth.signUpGuest(
        displayName: '凱文',
        birthday: '2000-04-01',
        birthdayConsent: true,
        today: DateTime(2026, 10, 26),
      );
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
      final now = world.clock.current;
      final selfId = world.auth.current!.id;
      for (final (id, name, memberRole) in [
        (selfId, '凱文', role),
        for (var i = 0; i < 8; i++) ('m$i', '成員$i', MemberRole.member),
      ]) {
        final member = TripMember(
          tripId: trip.id,
          userId: id,
          displayName: name,
          role: memberRole,
          isMinor: false,
          joinedAt: now,
        );
        world.database.members[trip.id]![id] = member;
        await world.trips.local.saveMember(member);
      }
      final proposed = DateTime.utc(2026, 11, 5, 9);
      final request = ModificationRequest(
        id: 'r1',
        tripId: trip.id,
        requesterId: 'm0',
        requesterName: '成員0',
        type: ModificationType.expectedReturnTime,
        proposedExpectedReturnAt: proposed,
        status: RequestStatus.pending,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 30)),
      );
      (world.database.requests[trip.id] ??= {})[request.id] = request;
      return (
        world: world,
        trip: trip,
        approve: AppStrings.approveReturn(
          TripTime.format(proposed, trip.timeZone),
        ),
      );
    }

    Future<void> openTrip(
      WidgetTester tester,
      TestWorld world,
      Trip trip,
    ) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        wrapPage(world.deps, TripDetailPage(tripId: trip.id)),
      );
      await tester.pumpAndSettle();
    }

    void expectManagement(String approve, Matcher matcher) {
      expect(find.byType(SwitchListTile), matcher);
      expect(find.text(AppStrings.saveExpectedReturn), matcher);
      expect(find.text(AppStrings.clearExpectedReturn), matcher);
      expect(find.text(AppStrings.pendingRequests), matcher);
      expect(find.text(approve), matcher);
    }

    testWidgets('App 版的隊長仍有全部管理操作', (tester) async {
      final setup = await tripAs(MemberRole.captain, web: false);
      await openTrip(tester, setup.world, setup.trip);

      expectManagement(setup.approve, findsOneWidget);
      expect(find.text(AppStrings.assignVice('成員0')), findsOneWidget);
      expect(find.byKey(const Key('web-manage-in-app')), findsNothing);
    });

    for (final role in [MemberRole.captain, MemberRole.viceCaptain]) {
      testWidgets('網頁版的${role.name}沒有管理操作，看得到要用 App 的說明，仍可發碼', (tester) async {
        final setup = await tripAs(role, web: true);
        await openTrip(tester, setup.world, setup.trip);

        expectManagement(setup.approve, findsNothing);
        expect(find.text(AppStrings.assignVice('成員0')), findsNothing);
        expect(find.text(AppStrings.viceRequired), findsNothing);
        expect(find.text(AppStrings.submitReturnRequest), findsNothing);
        expect(labeledField(AppStrings.returnDate), findsNothing);
        expect(find.byKey(const Key('web-manage-in-app')), findsOneWidget);

        final before = setup.world.database.invites.length;
        await tester.tap(find.byKey(const Key('issue-invite')));
        await tester.pumpAndSettle();
        expect(setup.world.database.invites.length, before + 1);
      });
    }

    testWidgets('網頁版的一般成員可以提交修改申請與發碼，沒有管理操作', (tester) async {
      final setup = await tripAs(MemberRole.member, web: true);
      final world = setup.world;
      await openTrip(tester, world, setup.trip);

      expectManagement(setup.approve, findsNothing);
      expect(find.byKey(const Key('web-manage-in-app')), findsNothing);

      final invitesBefore = world.database.invites.length;
      await tester.tap(find.byKey(const Key('issue-invite')));
      await tester.pumpAndSettle();
      expect(world.database.invites.length, invitesBefore + 1);

      final requestsBefore = world.database.requests[setup.trip.id]!.length;
      await enterLabeled(tester, AppStrings.returnDate, '2026-11-05');
      await enterLabeled(tester, AppStrings.returnTime, '20:00');
      await tester.tap(find.text(AppStrings.submitReturnRequest));
      await tester.pumpAndSettle();
      expect(
        world.database.requests[setup.trip.id]!.length,
        requestsBefore + 1,
      );
    });

    testWidgets('網頁版首頁的隊長不會看到點進去做不了的待辦', (tester) async {
      final setup = await tripAs(MemberRole.captain, web: true);
      await tester.pumpWidget(wrapPage(setup.world.deps, const HomePage()));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.boardSetReturn), findsNothing);
      expect(find.text(AppStrings.boardAssignVice), findsNothing);
      expect(find.text(AppStrings.boardReviewRequests(1)), findsNothing);
      expect(find.text(AppStrings.boardRequests), findsOneWidget);
    });

    testWidgets('網頁版分享看板重算後，畫面與文字都不列管理待辦', (tester) async {
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final setup = await tripAs(MemberRole.captain, web: true);
      await tester.pumpWidget(wrapPage(setup.world.deps, const HomePage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('share-board')));
      await tester.pumpAndSettle();

      final shared = setup.world.share.shared.single;
      for (final todo in [
        AppStrings.boardSetReturn,
        AppStrings.boardAssignVice,
        AppStrings.boardReviewRequests(1),
      ]) {
        expect(find.text(todo), findsNothing);
        expect(shared, isNot(contains(todo)));
      }
    });
  });

  test('KeyValueDocumentStore 存成一個字串，壞掉的資料不擋開啟', () async {
    final backing = <String, String>{'k': 'not json'};
    final store = KeyValueDocumentStore(
      key: 'k',
      readString: (key) => backing[key],
      writeString: (key, value) => backing[key] = value,
    );
    expect(await store.read(), isEmpty);
    await store.transaction((draft) => draft['a'] = 1);
    expect(backing['k'], '{"a":1}');
    expect((await store.read())['a'], 1);
  });
}
