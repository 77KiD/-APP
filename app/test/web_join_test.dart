import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/app/travel_app.dart';
import 'package:group_trip/core/persistence/key_value_document_store.dart';
import 'package:group_trip/features/home/home_page.dart';
import 'package:group_trip/features/trip/domain/invite_link.dart';
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
