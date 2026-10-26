import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/l10n/app_strings.dart';

/// 註冊規則在建立帳號之前跑完。未滿 13 歲不會呼叫 [create]。
class SignUpFlow {
  SignUpFlow({required this.create});

  final Future<UserAccount> Function(AcceptedSignUp request) create;

  Future<SignUpOutcome> run({
    required String email,
    required String password,
    required String displayName,
    required String birthday,
    required bool birthdayConsent,
    required DateTime today,
  }) async {
    final failure = validate(
      email: email,
      password: password,
      displayName: displayName,
      birthday: birthday,
      birthdayConsent: birthdayConsent,
      today: today,
    );
    if (failure != null) return SignUpOutcome.failure(failure);
    try {
      final account = await create(
        AcceptedSignUp(
          email: _email(email),
          password: password,
          displayName: displayName.trim(),
          birthday: birthday.trim(),
          today: today,
        ),
      );
      return SignUpOutcome.success(account);
    } on EmailInUseFailure catch (failure) {
      return SignUpOutcome.failure(failure);
    }
  }

  static SignUpFailure? validate({
    required String email,
    required String password,
    required String displayName,
    required String birthday,
    required bool birthdayConsent,
    required DateTime today,
  }) {
    if (!_emailPattern.hasMatch(_email(email))) {
      return const InvalidEmailFailure();
    }
    if (password.length < 8) return const WeakPasswordFailure();
    final name = displayName.trim();
    if (name.isEmpty) {
      return const InvalidDisplayNameFailure(AppStrings.emptyName);
    }
    if (name.length > 30) {
      return const InvalidDisplayNameFailure(AppStrings.nameTooLong);
    }
    if (CalendarDate.parse(birthday) == null) {
      return const InvalidBirthdayFailure();
    }
    if (AgePolicy.isUnder13(birthday.trim(), today)) {
      return const Under13Failure();
    }
    if (!birthdayConsent) return const BirthdayConsentFailure();
    return null;
  }

  static String _email(String email) => email.trim().toLowerCase();

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
}
