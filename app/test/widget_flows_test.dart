import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/app/travel_app.dart';
import 'package:group_trip/features/consent/presentation/consent_page.dart';
import 'package:group_trip/features/location_disclosure/presentation/location_disclosure_page.dart';
import 'package:group_trip/features/privacy/presentation/data_inventory_page.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/features/trip/presentation/create_trip_page.dart';
import 'package:group_trip/features/trip/presentation/trip_detail_page.dart';
import 'package:group_trip/l10n/app_strings.dart';

import 'support/harness.dart';

void main() {
  testWidgets('未滿 13 歲的註冊表單會擋住，而且欄位能用鍵盤操作', (tester) async {
    final world = TestWorld(now: DateTime(2026, 10, 26));
    await tester.pumpWidget(TravelApp(deps: world.deps));
    await tester.tap(find.text(AppStrings.goToSignUp));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(AppStrings.email), findsWidgets);
    expect(find.text(AppStrings.birthdayPurpose), findsOneWidget);
    expect(find.text(AppStrings.submitSignUp), findsOneWidget);
    expect(find.byType(IconButton), findsNothing);

    await enterLabeled(tester, AppStrings.email, 'kid@example.com');
    await enterLabeled(tester, AppStrings.password, 'password1');
    await enterLabeled(tester, AppStrings.displayName, '小朋友');
    await enterLabeled(tester, AppStrings.birthday, '2016-04-01');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text(AppStrings.submitSignUp));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.under13), findsOneWidget);
    final error = tester.getSemantics(find.text(AppStrings.under13));
    expect(error.flagsCollection.isLiveRegion, isTrue);
    expect(world.auth.current, isNull);

    await enterLabeled(tester, AppStrings.birthday, '2000-04-01');
    await tester.tap(find.text(AppStrings.submitSignUp));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.consentTitle), findsOneWidget);
    expect(world.analytics.enableCalls, isEmpty);
  });

  testWidgets('同意前的畫面不會打開分析，拒絕後仍然關閉', (tester) async {
    final world = TestWorld();
    await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: DateTime(2026, 10, 26),
    );
    await tester.pumpWidget(wrapPage(world.deps, const ConsentPage()));
    expect(find.text(AppStrings.consentDecline), findsOneWidget);
    await tester.tap(find.text(AppStrings.consentDecline));
    await tester.pumpAndSettle();
    expect(world.analytics.enabled, isFalse);
    expect(world.crashes.enabled, isFalse);
    expect(world.auth.current!.consentDecided, isTrue);
  });

  testWidgets('定位說明按鈕不會向系統要求權限', (tester) async {
    final world = TestWorld();
    await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: DateTime(2026, 10, 26),
    );
    await tester.pumpWidget(wrapPage(world.deps, const LocationDisclosurePage()));
    expect(find.text(AppStrings.disclosureBody), findsOneWidget);
    await tester.tap(find.text(AppStrings.disclosureAck));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.disclosureSaved), findsOneWidget);
    expect(world.permissionClient.calls, 0);
    expect(await world.disclosure.isAcknowledged(world.auth.current!.id), isTrue);
    expect(await world.deps.location.requestForSendLocation(), isFalse);
    expect(world.permissionClient.calls, 1);
  });

  testWidgets('資料說明寫明這一版不收集 FCM 權杖', (tester) async {
    final world = TestWorld();
    await tester.pumpWidget(wrapPage(world.deps, const DataInventoryPage()));
    expect(find.text(AppStrings.inventoryFcm), findsOneWidget);
    expect(find.text(AppStrings.inventoryBirthday), findsOneWidget);
  });

  testWidgets('斷網仍可建立旅程並看到邀請碼與隊長', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final world = TestWorld(online: false);
    await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    );
    await tester.pumpWidget(
      wrapPage(
        world.deps,
        const CreateTripPage(initialTimeZone: 'Asia/Taipei'),
      ),
    );
    await enterLabeled(tester, AppStrings.tripTitle, '京都自由行');
    await enterLabeled(tester, AppStrings.startDate, '2026-11-01');
    await enterLabeled(tester, AppStrings.endDate, '2026-11-05');
    await enterLabeled(tester, AppStrings.returnDate, '2026-11-05');
    await enterLabeled(tester, AppStrings.returnTime, '18:00');
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, AppStrings.submitCreateTrip),
    );
    await tester.tap(
      find.widgetWithText(FilledButton, AppStrings.submitCreateTrip),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.roleCaptain), findsOneWidget);
    expect(find.byKey(const Key('invite-code')), findsOneWidget);
    expect(
      find.text(AppStrings.inviteRemaining(const Duration(hours: 1))),
      findsOneWidget,
    );
    expect(find.text(AppStrings.inviteAdvisory), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byKey(const Key('issue-invite'))).onPressed,
      isNotNull,
    );
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
    expect((await world.trips.listMyTrips()).single.publicInvite, isFalse);
    expect(
      find.bySemanticsLabel(AppStrings.avatarLabel('小美'), skipOffstage: false),
      findsOneWidget,
    );
    expect(world.database.trips, isEmpty);
    final trip = (await world.trips.listMyTrips()).single;
    expect(trip.endDate, '2026-11-05');
    expect(trip.expectedReturnAt, isNotNull);

    world.connectivity.isOnline = true;
    await world.trips.sync();
    expect(world.database.trips, hasLength(1));
  });

  testWidgets('成員名單顯示隊長、副隊長、一般成員', (tester) async {
    final world = TestWorld();
    await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    );
    final trip = await world.trips.createTrip(
      const NewTripForm(
        title: '測試團',
        startDate: '2026-12-01',
        endDate: '2026-12-03',
        timeZone: 'Asia/Taipei',
        returnDate: '',
        returnTime: '',
      ),
    );
    final local = world.trips.local;
    for (final member in [
      (id: 'v', name: '阿強', role: MemberRole.viceCaptain),
      (id: 'm', name: '小華', role: MemberRole.member),
    ]) {
      await local.saveMember(
        TripMember(
          tripId: trip.id,
          userId: member.id,
          displayName: member.name,
          role: member.role,
          isMinor: false,
          joinedAt: world.clock.current,
        ),
      );
    }
    world.connectivity.isOnline = false;
    await tester.pumpWidget(wrapPage(world.deps, TripDetailPage(tripId: trip.id)));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.roleCaptain, skipOffstage: false), findsOneWidget);
    expect(find.text(AppStrings.roleVice, skipOffstage: false), findsOneWidget);
    expect(find.text(AppStrings.roleMember, skipOffstage: false), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        AppStrings.avatarLabel('阿強'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.textContaining(AppStrings.inviteCode), findsWidgets);
  });

  testWidgets('公開邀請關閉時，一般成員的產生按鈕不能按', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final world = TestWorld();
    await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    );
    final trip = await world.trips.createTrip(
      const NewTripForm(
        title: '測試團',
        startDate: '2026-12-01',
        endDate: '2026-12-03',
        timeZone: 'Asia/Taipei',
        returnDate: '',
        returnTime: '',
      ),
    );
    await world.trips.setPublicInvite(tripId: trip.id, enabled: false);
    final joined = await world.auth.signUp(
      email: 'hua@example.com',
      password: 'password1',
      displayName: '小華',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    );
    final member = joined.account!;
    await world.remote.upsertMember(
      TripMember(
        tripId: trip.id,
        userId: member.id,
        displayName: member.displayName,
        role: MemberRole.member,
        isMinor: false,
        joinedAt: world.clock.current,
      ),
    );
    await tester.pumpWidget(wrapPage(world.deps, TripDetailPage(tripId: trip.id)));
    await tester.pumpAndSettle();

    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text(AppStrings.inviteRestricted), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byKey(const Key('issue-invite'))).onPressed,
      isNull,
    );
  });

  testWidgets('副隊長可以關閉公開邀請', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final world = TestWorld();
    await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    );
    final trip = await world.trips.createTrip(
      const NewTripForm(
        title: '測試團',
        startDate: '2026-12-01',
        endDate: '2026-12-03',
        timeZone: 'Asia/Taipei',
        returnDate: '',
        returnTime: '',
      ),
    );
    final vice = (await world.auth.signUp(
      email: 'vice@example.com',
      password: 'password1',
      displayName: '阿強',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    )).account!;
    await world.remote.upsertMember(
      TripMember(
        tripId: trip.id,
        userId: vice.id,
        displayName: vice.displayName,
        role: MemberRole.viceCaptain,
        isMinor: false,
        joinedAt: world.clock.current,
      ),
    );
    await tester.pumpWidget(wrapPage(world.deps, TripDetailPage(tripId: trip.id)));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsOneWidget);
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect((await world.trips.getTrip(trip.id)).publicInvite, isFalse);
    expect(find.text(AppStrings.roleVice), findsWidgets);
  });
}
