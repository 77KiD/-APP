import 'package:group_trip/l10n/app_strings.dart';

class UserAccount {
  const UserAccount({
    required this.id,
    required this.email,
    required this.displayName,
    required this.birthday,
    required this.consentDecided,
    required this.analyticsConsent,
    required this.crashlyticsConsent,
    this.photoUrl,
  });

  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;

  /// `YYYY-MM-DD`。只留在帳號，不複製進旅程。
  final String birthday;
  final bool consentDecided;
  final bool analyticsConsent;
  final bool crashlyticsConsent;

  UserAccount copy({
    bool? consentDecided,
    bool? analyticsConsent,
    bool? crashlyticsConsent,
    String? displayName,
    String? photoUrl,
  }) {
    return UserAccount(
      id: id,
      email: email,
      displayName: displayName ?? this.displayName,
      birthday: birthday,
      photoUrl: photoUrl ?? this.photoUrl,
      consentDecided: consentDecided ?? this.consentDecided,
      analyticsConsent: analyticsConsent ?? this.analyticsConsent,
      crashlyticsConsent: crashlyticsConsent ?? this.crashlyticsConsent,
    );
  }

  /// 給 Firestore `users/{uid}` 的公開欄位。不含密碼。
  Map<String, Object?> toPublicMap() => {
    'displayName': displayName,
    'birthday': birthday,
    'photoUrl': photoUrl,
    'analyticsConsent': analyticsConsent,
    'crashlyticsConsent': crashlyticsConsent,
    'consentDecided': consentDecided,
  };
}

sealed class SignUpFailure {
  const SignUpFailure();
  String get message;
}

class Under13Failure extends SignUpFailure {
  const Under13Failure();
  @override
  String get message => AppStrings.under13;
}

class BirthdayConsentFailure extends SignUpFailure {
  const BirthdayConsentFailure();
  @override
  String get message => AppStrings.needBirthdayConsent;
}

class InvalidEmailFailure extends SignUpFailure {
  const InvalidEmailFailure();
  @override
  String get message => AppStrings.invalidEmail;
}

class WeakPasswordFailure extends SignUpFailure {
  const WeakPasswordFailure();
  @override
  String get message => AppStrings.weakPassword;
}

class InvalidDisplayNameFailure extends SignUpFailure {
  const InvalidDisplayNameFailure(this.message);
  @override
  final String message;
}

class InvalidBirthdayFailure extends SignUpFailure {
  const InvalidBirthdayFailure();
  @override
  String get message => AppStrings.invalidDate;
}

class EmailInUseFailure extends SignUpFailure {
  const EmailInUseFailure();
  @override
  String get message => AppStrings.emailInUse;
}

class SignUpOutcome {
  const SignUpOutcome.success(this.account) : failure = null;
  const SignUpOutcome.failure(this.failure) : account = null;

  final UserAccount? account;
  final SignUpFailure? failure;
}

class AcceptedSignUp {
  const AcceptedSignUp({
    required this.email,
    required this.password,
    required this.displayName,
    required this.birthday,
    required this.today,
  });

  final String email;
  final String password;
  final String displayName;
  final String birthday;
  final DateTime today;
}

sealed class SignInFailure {
  const SignInFailure();
  String get message;
}

class WrongCredentialsFailure extends SignInFailure {
  const WrongCredentialsFailure();
  @override
  String get message => AppStrings.wrongCredentials;
}

class MissingProfileFailure extends SignInFailure {
  const MissingProfileFailure();
  @override
  String get message => AppStrings.missingProfile;
}

class SignInOutcome {
  const SignInOutcome.success(this.account) : failure = null;
  const SignInOutcome.failure(this.failure) : account = null;

  final UserAccount? account;
  final SignInFailure? failure;
}

abstract class AuthRepository {
  UserAccount? get current;

  Stream<UserAccount?> watch();

  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String displayName,
    required String birthday,
    required bool birthdayConsent,
    required DateTime today,
  });

  Future<SignInOutcome> signIn({
    required String email,
    required String password,
  });

  Future<void> signOut();

  Future<UserAccount> updateConsent({
    required bool analytics,
    required bool crashlytics,
  });
}
