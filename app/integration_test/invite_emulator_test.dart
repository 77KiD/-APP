import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:group_trip/core/ids/id_generator.dart';
import 'package:group_trip/core/persistence/json_document_store.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/features/auth/data/firebase_auth_repository.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/trip/data/firestore_trip_remote.dart';
import 'package:group_trip/features/trip/data/offline_trip_repository.dart';
import 'package:group_trip/features/trip/data/trip_local_store.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/l10n/app_strings.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:web/web.dart' as web;

const _firestoreHost = String.fromEnvironment('FIRESTORE_EMULATOR_HOST');
const _firestorePort = int.fromEnvironment(
  'FIRESTORE_EMULATOR_PORT',
  defaultValue: 8080,
);
const _authHost = String.fromEnvironment(
  'AUTH_EMULATOR_HOST',
  defaultValue: '127.0.0.1',
);
const _authPort = int.fromEnvironment('AUTH_EMULATOR_PORT', defaultValue: 9099);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InviteEmulatorApp());
}

class InviteEmulatorApp extends StatefulWidget {
  const InviteEmulatorApp({super.key});

  @override
  State<InviteEmulatorApp> createState() => _InviteEmulatorAppState();
}

class _InviteEmulatorAppState extends State<InviteEmulatorApp> {
  String _status = 'RUNNING';

  @override
  void initState() {
    super.initState();
    _publish(_status);
    _run();
  }

  Future<void> _run() async {
    try {
      if (_firestoreHost.isEmpty) {
        throw StateError('FIRESTORE_EMULATOR_HOST dart-define is missing');
      }
      tzdata.initializeTimeZones();
      _setStatus('RUNNING init');
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'demo-key',
          appId: '1:1:web:invite-emulator',
          messagingSenderId: '1',
          projectId: 'demo-app',
        ),
      );
      final firestore = FirebaseFirestore.instance;
      firestore.useFirestoreEmulator(_firestoreHost, _firestorePort);
      firestore.settings = const Settings(persistenceEnabled: false);
      await FirebaseAuth.instance.useAuthEmulator(_authHost, _authPort);
      final authRepo = FirebaseAuthRepository(
        auth: FirebaseAuth.instance,
        firestore: firestore,
        consentStore: MemoryDocumentStore(),
      );
      _setStatus('RUNNING signup');
      await _happyPath(authRepo);
      _setStatus('RUNNING join errors');
      await _joinErrors(authRepo);
      _setStatus('RUNNING skew');
      await _clockSkew(authRepo);
      _setStatus('ALL PASS');
    } catch (error, stack) {
      _setStatus('FAIL $error\n$stack');
    }
  }

  void _setStatus(String value) {
    _publish(value);
    if (mounted) setState(() => _status = value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(body: Text(_status)),
    );
  }
}

void _publish(String message) {
  final title = message.startsWith('ALL PASS')
      ? 'ALL PASS'
      : message.startsWith('FAIL')
      ? 'FAIL'
      : message;
  web.document.title = title;
  final node = web.document.createElement('pre');
  node.textContent = message;
  web.document.body?.appendChild(node);
}

void _check(bool condition, String label) {
  if (!condition) throw StateError(label);
}

Future<void> _happyPath(FirebaseAuthRepository authRepo) async {
  final clock = FixedDeviceClock(DateTime.now().toUtc());
  await _signUp(authRepo, '隊長');
  final captainRepo = _repository(authRepo, clock);
  final trip = await captainRepo.createTrip(_form('甲團'));
  _check(trip.inviteCode.isNotEmpty, '建立後應有邀請碼');
  final issued = await captainRepo.issueInviteCode(trip.id);
  _check(issued.code != trip.inviteCode, '新碼應不同');
  final visible = await captainRepo.listInvites(trip.id);
  final codes = visible.map((invite) => invite.code).toSet();
  _check(codes.contains(trip.inviteCode), '建立時的碼要留在畫面上');
  _check(codes.contains(issued.code), '新產生的碼要留在畫面上');
  _check(await captainRepo.remote.fetchInvite(issued.code) != null, '伺服器要有這個碼');

  await authRepo.signOut();
  await _signUp(authRepo, '成員');
  final memberRepo = _repository(authRepo, clock);
  final joined = await memberRepo.joinWithInviteCode(issued.code);
  _check(joined.id == trip.id, 'B 應加入 A 的旅程');
  final members = await memberRepo.listMembers(trip.id);
  _check(
    members.map((member) => member.userId).contains(authRepo.current?.id),
    'B 應在成員名單',
  );
  await authRepo.signOut();
}

Future<void> _joinErrors(FirebaseAuthRepository authRepo) async {
  final clock = FixedDeviceClock(DateTime.now().toUtc());
  await _signUp(authRepo, '查碼');
  final repo = _repository(authRepo, clock);
  try {
    await repo.joinWithInviteCode('NOSUCH01');
    throw StateError('不存在的碼不該加入成功');
  } on InviteNotFoundException catch (error) {
    _check(error.message == AppStrings.inviteNotFound, '找不到的訊息');
  }

  await authRepo.signOut();
  final bare = await FirebaseAuth.instance.createUserWithEmailAndPassword(
    email: _email('bare'),
    password: 'password1',
  );
  final bareRepo = _repository(authRepo, clock, accountId: bare.user!.uid);
  try {
    await bareRepo.joinWithInviteCode('NOSUCH01');
    throw StateError('沒有帳號文件不該變成找不到');
  } on InvitePermissionException catch (error) {
    _check(error.message == AppStrings.invitePermissionOrNetwork, '權限或網路的訊息');
  }
  await FirebaseAuth.instance.signOut();
}

Future<void> _clockSkew(FirebaseAuthRepository authRepo) async {
  final clock = FixedDeviceClock(DateTime.now().toUtc());
  await _signUp(authRepo, '時鐘');
  final repo = _repository(authRepo, clock);
  final trip = await repo.createTrip(_form('時鐘團'));
  final before = (await repo.listInvites(trip.id)).map((invite) => invite.code).toSet();

  clock.current = DateTime.now().toUtc().add(const Duration(minutes: 2));
  final issued = await repo.issueInviteCode(trip.id);
  _check(issued.code.isNotEmpty, '快 2 分鐘仍應產生邀請碼');
  _check(
    (await repo.listInvites(trip.id)).any((invite) => invite.code == issued.code),
    '快 2 分鐘的碼要顯示',
  );

  clock.current = DateTime.now().toUtc().add(const Duration(minutes: 10));
  final logs = <String>[];
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    logs.add(message ?? '');
  };
  try {
    await repo.issueInviteCode(trip.id);
    throw StateError('快 10 分鐘不該產生邀請碼');
  } on ServerWriteException catch (error) {
    _check(error.message == AppStrings.serverWriteFailed, '寫入失敗的訊息');
  } finally {
    debugPrint = previous;
  }
  _check(logs.join('\n').contains('permission-denied'), '要記下 FirebaseException');
  final after = (await repo.listInvites(trip.id)).map((invite) => invite.code).toSet();
  _check(after.contains(issued.code), '原本快 2 分鐘的碼還在');
  _check(after.difference(before).length == 1, '快 10 分鐘不能多一個碼');
  await authRepo.signOut();
}

int _serial = 0;

String _email(String label) {
  _serial += 1;
  return '$label-$_serial@example.com';
}

Future<UserAccount> _signUp(FirebaseAuthRepository authRepo, String name) async {
  final outcome = await authRepo.signUp(
    email: _email(name),
    password: 'password1',
    displayName: name,
    birthday: '2000-01-01',
    birthdayConsent: true,
    today: DateTime.now().toUtc(),
  );
  final account = outcome.account;
  if (outcome.failure != null || account == null) {
    throw StateError('註冊失敗 ${outcome.failure?.message}');
  }
  return account;
}

OfflineTripRepository _repository(
  FirebaseAuthRepository authRepo,
  DeviceClock clock, {
  String? accountId,
}) {
  final auth = FirebaseAuth.instance;
  return OfflineTripRepository(
    local: TripLocalStore(MemoryDocumentStore()),
    remote: FirestoreTripRemote(
      firestore: FirebaseFirestore.instance,
      currentUserId: () => accountId ?? auth.currentUser?.uid ?? '',
    ),
    currentAccount: () {
      final current = authRepo.current;
      if (current != null) return current;
      final uid = accountId ?? auth.currentUser?.uid;
      if (uid == null) return null;
      return UserAccount(
        id: uid,
        email: auth.currentUser?.email ?? '',
        displayName: '未註冊',
        birthday: '2000-01-01',
        consentDecided: true,
        analyticsConsent: false,
        crashlyticsConsent: false,
      );
    },
    clock: clock,
    ids: RandomIdGenerator(),
    connectivity: ConnectivityProbe(isOnline: true),
  );
}

NewTripForm _form(String title) {
  return NewTripForm(
    title: title,
    startDate: '2030-04-01',
    endDate: '2030-04-03',
    timeZone: 'Asia/Taipei',
    returnDate: '',
    returnTime: '',
  );
}
