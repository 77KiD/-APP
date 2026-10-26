import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:group_trip/core/persistence/json_document_store.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/data/firestore_schema.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/auth/domain/sign_up_flow.dart';
import 'package:group_trip/features/trip/data/firestore_paths.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    this.consentStore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  /// 分析與當機報告的同意只留在這台手機。規則不允許寫進 users。
  final JsonDocumentStore? consentStore;
  final _updates = StreamController<UserAccount?>.broadcast();
  UserAccount? _current;
  late final Stream<UserAccount?> _watch = _watchImpl();

  Future<void> restore() async {
    await _auth.authStateChanges().first;
    final user = _auth.currentUser;
    if (user == null) return;
    _current = await _load(user.uid);
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
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: request.email,
        password: request.password,
      );
      final user = credential.user;
      if (user == null) throw const MissingProfileFailure();
      await user.updateDisplayName(request.displayName);
      final account = UserAccount(
        id: user.uid,
        email: request.email,
        displayName: request.displayName,
        birthday: request.birthday,
        consentDecided: false,
        analyticsConsent: false,
        crashlyticsConsent: false,
      );
      try {
        await _users.doc(account.id).set({
          FirestoreSchema.birthdate: _utcMidnight(account.birthday),
          FirestoreSchema.displayName: account.displayName,
          FirestoreSchema.photoUrl: account.photoUrl,
          FirestoreSchema.createdAt: FieldValue.serverTimestamp(),
          FirestoreSchema.updatedAt: FieldValue.serverTimestamp(),
        });
      } on FirebaseException {
        await _discard(user);
        throw const ProfileWriteFailure();
      }
      _emit(account);
      return account;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'email-already-in-use') throw const EmailInUseFailure();
      throw const WrongCredentialsFailure();
    }
  }

  @override
  Future<SignInOutcome> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final user = credential.user;
      if (user == null) return const SignInOutcome.failure(WrongCredentialsFailure());
      final account = await _load(user.uid);
      if (account == null) {
        return const SignInOutcome.failure(MissingProfileFailure());
      }
      _emit(account);
      return SignInOutcome.success(account);
    } on FirebaseAuthException {
      return const SignInOutcome.failure(WrongCredentialsFailure());
    }
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
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
    final store = consentStore;
    if (store != null) {
      await store.transaction((draft) {
        draft[account.id] = {
          LocalOnlyFields.consentDecided: true,
          LocalOnlyFields.analyticsConsent: analytics,
          LocalOnlyFields.crashlyticsConsent: crashlytics,
        };
      });
    }
    _emit(updated);
    return updated;
  }

  Future<void> _discard(User user) async {
    try {
      await user.delete();
    } catch (_) {
      // 刪不掉時至少不要留在已登入狀態。
    }
    try {
      await _auth.signOut();
    } catch (_) {}
  }

  Timestamp _utcMidnight(String birthday) {
    final date = CalendarDate.parse(birthday);
    if (date == null) {
      return Timestamp.fromDate(DateTime.utc(1970));
    }
    return Timestamp.fromDate(DateTime.utc(date.year, date.month, date.day));
  }

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(FirestorePaths.users);

  Future<UserAccount?> _load(String uid) async {
    final snap = await _users.doc(uid).get();
    final data = snap.data();
    if (data == null) return null;
    final email = _auth.currentUser?.email ?? '';
    final consent = await _readConsent(uid);
    return UserAccount(
      id: uid,
      email: email,
      displayName: '${data[FirestoreSchema.displayName] ?? ''}',
      birthday: _birthdateText(data[FirestoreSchema.birthdate]),
      photoUrl: data[FirestoreSchema.photoUrl] as String?,
      consentDecided: consent.decided,
      analyticsConsent: consent.analytics,
      crashlyticsConsent: consent.crashlytics,
    );
  }

  Future<({bool decided, bool analytics, bool crashlytics})> _readConsent(
    String uid,
  ) async {
    final store = consentStore;
    if (store == null) {
      return (decided: false, analytics: false, crashlytics: false);
    }
    final data = await store.read();
    final raw = data[uid];
    if (raw is! Map) {
      return (decided: false, analytics: false, crashlytics: false);
    }
    return (
      decided: raw[LocalOnlyFields.consentDecided] == true,
      analytics: raw[LocalOnlyFields.analyticsConsent] == true,
      crashlytics: raw[LocalOnlyFields.crashlyticsConsent] == true,
    );
  }

  String _birthdateText(Object? raw) {
    if (raw is Timestamp) {
      final date = raw.toDate().toUtc();
      return CalendarDate(date.year, date.month, date.day).format();
    }
    if (raw is String) return raw;
    return '';
  }

  void _emit(UserAccount? account) {
    _current = account;
    if (!_updates.isClosed) _updates.add(account);
  }
}
