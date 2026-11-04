import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/features/trip/presentation/join_trip_page.dart';
import 'package:group_trip/l10n/app_strings.dart';

import 'support/harness.dart';

void main() {
  for (final configured in [false, true]) {
    testWidgets(
      configured ? '連線版加入頁不顯示本機模式說明，找不到碼照原本訊息' : '本機模式加入頁說明邀請碼無法跨手機，找不到碼時說明原因',
      (tester) async {
        final world = TestWorld(firebaseConfigured: configured);
        await world.auth.signUp(
          email: 'user@example.com',
          password: 'password1',
          displayName: '小明',
          birthday: '2000-01-01',
          birthdayConsent: true,
          today: DateTime(2026, 10, 26),
        );
        await tester.pumpWidget(wrapPage(world.deps, const JoinTripPage()));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('local-mode-invite-notice')),
          configured ? findsNothing : findsOneWidget,
        );

        await enterLabeled(tester, AppStrings.inviteCodeField, 'NOPE1234');
        await tester.tap(
          find.widgetWithText(FilledButton, AppStrings.submitJoin),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            configured
                ? AppStrings.inviteNotFound
                : AppStrings.localModeInviteNotFound,
          ),
          findsOneWidget,
        );
      },
    );
  }
}
