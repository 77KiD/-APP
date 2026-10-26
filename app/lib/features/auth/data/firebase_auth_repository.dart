import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/auth/domain/sign_up_flow.dart';
import 'package:group_trip/features/trip/data/firestore_paths.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
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
      await _users.doc(account.id).set({
        ...account.toPublicMap(),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
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
    await _users.doc(account.id).set({
      ...updated.toPublicMap(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));
    _emit(updated);
    return updated;
  }

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(FirestorePaths.users);

  Future<UserAccount?> _load(String uid) async {
    final snap = await _users.doc(uid).get();
    final data = snap.data();
    if (data == null) return null;
    final email = _auth.currentUser?.email ?? '';
    return UserAccount(
      id: uid,
      email: email,
      displayName: '${data['displayName'] ?? ''}',
      birthday: '${data['birthday'] ?? ''}',
      photoUrl: data['photoUrl'] as String?,
      consentDecided: data['consentDecided'] == true,
      analyticsConsent: data['analyticsConsent'] == true,
      crashlyticsConsent: data['crashlyticsConsent'] == true,
    );
  }

  void _emit(UserAccount? account) {
    _current = account;
    if (!_updates.isClosed) _updates.add(account);
  }
}
