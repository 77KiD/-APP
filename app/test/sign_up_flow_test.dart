import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/auth/domain/sign_up_flow.dart';
import 'package:group_trip/l10n/app_strings.dart';
import 'support/harness.dart';

void main() {
  final today = DateTime(2026, 10, 26);

  test('未滿 13 歲不會呼叫建立帳號', () async {
    var calls = 0;
    final flow = SignUpFlow(
      create: (request) async {
        calls += 1;
        return UserAccount(
          id: 'should-not',
          email: request.email,
          displayName: request.displayName,
          birthday: request.birthday,
          consentDecided: false,
          analyticsConsent: false,
          crashlyticsConsent: false,
        );
      },
    );
    final outcome = await flow.run(
      email: 'kid@example.com',
      password: 'password1',
      displayName: '小朋友',
      birthday: '2016-01-01',
      birthdayConsent: true,
      today: today,
    );
    expect(calls, 0);
    expect(outcome.failure, isA<Under13Failure>());
    expect(outcome.failure!.message, AppStrings.under13);
    expect(outcome.account, isNull);
  });

  test('本機註冊會擋下未滿 13 歲，滿 13 歲才會留下生日', () async {
    final world = TestWorld(now: today);
    final blocked = await world.auth.signUp(
      email: 'kid@example.com',
      password: 'password1',
      displayName: '小朋友',
      birthday: '2014-10-27',
      birthdayConsent: true,
      today: today,
    );
    expect(blocked.failure, isA<Under13Failure>());
    expect(world.auth.current, isNull);

    final adult = await world.auth.signUp(
      email: 'Ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-05-01',
      birthdayConsent: true,
      today: today,
    );
    expect(adult.account?.birthday, '2000-05-01');
    expect(adult.account?.email, 'ada@example.com');
    expect(adult.account!.toPublicMap().containsKey('passwordHash'), isFalse);

    final again = await world.auth.signIn(
      email: 'ada@example.com',
      password: 'wrong-password',
    );
    expect(again.failure, isA<WrongCredentialsFailure>());
    final signedIn = await world.auth.signIn(
      email: 'ada@example.com',
      password: 'password1',
    );
    expect(signedIn.account?.displayName, '小美');
  });

  test('沒有勾選生日同意不會建立帳號', () async {
    final world = TestWorld(now: today);
    final outcome = await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-05-01',
      birthdayConsent: false,
      today: today,
    );
    expect(outcome.failure, isA<BirthdayConsentFailure>());
    expect(world.auth.current, isNull);
  });
}
