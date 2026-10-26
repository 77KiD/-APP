import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:group_trip/core/ids/id_generator.dart';
import 'package:group_trip/core/persistence/json_document_store.dart';
import 'package:group_trip/data/firestore_schema.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/auth/domain/sign_up_flow.dart';

class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository({required this.store, required this.ids});

  final JsonDocumentStore store;
  final IdGenerator ids;
  final _updates = StreamController<UserAccount?>.broadcast();
  UserAccount? _current;
  late final Stream<UserAccount?> _watch = _watchImpl();

  Future<void> restore() async {
    final data = await store.read();
    final session = data['sessionUserId'];
    if (session is! String) return;
    _current = _accountFromUsers(data, session);
  }

  @override
  UserAccount? get current => _current;

  @override
  Stream<UserAccount?> watch() => _watch;

  Stream<UserAccount?> _watchImpl() async* {
    yield _current;
    yield* _updates.stream;
  }

  @override
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String displayName,
    required String birthday,
    required bool birthdayConsent,
    required DateTime today,
  }) {
    return SignUpFlow(create: _create).run(
      email: email,
      password: password,
      displayName: displayName,
      birthday: birthday,
      birthdayConsent: birthdayConsent,
      today: today,
    );
  }

  Future<UserAccount> _create(AcceptedSignUp request) async {
    final existing = await _findByEmail(request.email);
    if (existing != null) throw const EmailInUseFailure();
    final account = UserAccount(
      id: ids.next(),
      email: request.email,
      displayName: request.displayName,
      birthday: request.birthday,
      consentDecided: false,
      analyticsConsent: false,
      crashlyticsConsent: false,
    );
    final salt = ids.next();
    await store.transaction((draft) {
      final users = _users(draft);
      users[account.id] = {
        ...account.toDeviceMap(),
        'passwordSalt': salt,
        'passwordHash': _hash(password: request.password, salt: salt),
      };
      draft['users'] = users;
      draft['sessionUserId'] = account.id;
    });
    _emit(account);
    return account;
  }

  @override
  Future<SignInOutcome> signIn({
    required String email,
    required String password,
  }) async {
    final data = await store.read();
    final record = _findRecord(data, email.trim().toLowerCase());
    if (record == null) return const SignInOutcome.failure(WrongCredentialsFailure());
    final salt = '${record['passwordSalt']}';
    if (_hash(password: password, salt: salt) != record['passwordHash']) {
      return const SignInOutcome.failure(WrongCredentialsFailure());
    }
    final account = _accountFromRecord(record);
    if (account == null) {
      return const SignInOutcome.failure(MissingProfileFailure());
    }
    await store.transaction((draft) {
      draft['sessionUserId'] = account.id;
    });
    _emit(account);
    return SignInOutcome.success(account);
  }

  @override
  Future<void> signOut() async {
    await store.transaction((draft) {
      draft.remove('sessionUserId');
    });
    _emit(null);
  }

  @override
  Future<UserAccount> updateConsent({
    required bool analytics,
    required bool crashlytics,
  }) async {
    final account = _current;
    if (account == null) throw const MissingProfileFailure();
    final updated = account.copy(
      consentDecided: true,
      analyticsConsent: analytics,
      crashlyticsConsent: crashlytics,
    );
    await store.transaction((draft) {
      final users = _users(draft);
      final current = users[account.id];
      final record = current is Map
          ? Map<String, dynamic>.from(current)
          : <String, dynamic>{};
      record.addAll(updated.toDeviceMap());
      users[account.id] = record;
      draft['users'] = users;
    });
    _emit(updated);
    return updated;
  }

  void _emit(UserAccount? account) {
    _current = account;
    if (!_updates.isClosed) _updates.add(account);
  }

  Future<UserAccount?> _findByEmail(String email) async {
    final record = _findRecord(await store.read(), email);
    return record == null ? null : _accountFromRecord(record);
  }

  Map<String, dynamic>? _findRecord(Map<String, dynamic> data, String email) {
    final users = _users(data);
    for (final raw in users.values) {
      if (raw is Map && raw[LocalOnlyFields.email] == email) {
        return Map<String, dynamic>.from(raw);
      }
    }
    return null;
  }

  UserAccount? _accountFromUsers(Map<String, dynamic> data, String id) {
    final raw = _users(data)[id];
    if (raw is! Map) return null;
    return _accountFromRecord(Map<String, dynamic>.from(raw));
  }

  UserAccount? _accountFromRecord(Map<String, dynamic> record) {
    final id = record[LocalOnlyFields.documentId];
    final email = record[LocalOnlyFields.email];
    final birthday =
        record[LocalOnlyFields.birthday] ?? record[FirestoreSchema.birthdate];
    if (id is! String || email is! String || birthday is! String) return null;
    return UserAccount(
      id: id,
      email: email,
      displayName: '${record[FirestoreSchema.displayName] ?? ''}',
      birthday: birthday,
      photoUrl: record[FirestoreSchema.photoUrl] as String?,
      consentDecided: record[LocalOnlyFields.consentDecided] == true,
      analyticsConsent: record[LocalOnlyFields.analyticsConsent] == true,
      crashlyticsConsent: record[LocalOnlyFields.crashlyticsConsent] == true,
    );
  }

  Map<String, dynamic> _users(Map<String, dynamic> data) {
    final value = data['users'];
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  String _hash({required String password, required String salt}) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }
}
