import 'dart:convert';
import 'dart:js_interop';

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
  runApp(const Verify41App());
}

class Verify41App extends StatefulWidget {
  const Verify41App({super.key});

  @override
  State<Verify41App> createState() => _Verify41AppState();
}

class _Verify41AppState extends State<Verify41App> {
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
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'demo-key',
          appId: '1:1:web:verify-41',
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
      final notes = await _scenario(authRepo);
      _setStatus('ALL PASS\n$notes');
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
    return MaterialApp(home: Scaffold(body: Text(_status)));
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

final _codePattern = RegExp(r'^[A-Z0-9]{8,12}$');

void _codeOk(String code, String label) {
  _check(_codePattern.hasMatch(code), '$label 應為 8–12 碼，實際「$code」');
}

int _serial = 0;

String _email(String label) {
  _serial += 1;
  return 'v41-$label-$_serial@example.com';
}

class _Person {
  _Person({
    required this.email,
    required this.uid,
    required this.repo,
    required this.store,
    required this.name,
  });

  final String email;
  final String uid;
  final String name;
  final MemoryDocumentStore store;
  final OfflineTripRepository repo;
}

Future<String> _scenario(FirebaseAuthRepository authRepo) async {
  final clock = FixedDeviceClock(DateTime.now().toUtc());
  final leader = await _signUp(authRepo, 'leader', clock);
  final trip = await leader.repo.createTrip(_form('驗證團', '2030-04-01', '2030-04-03'));
  _codeOk(trip.inviteCode, '建立時的邀請碼');
  final stored = await leader.repo.remote.fetchInvite(trip.inviteCode);
  _check(stored != null, '建立後伺服器應有邀請碼');
  final hour = stored!.expiresAt.difference(stored.createdAt);
  _check(
    hour.inMinutes >= 55 && hour.inMinutes <= 65,
    '建立時效期應約 1 小時，實際 ${hour.inMinutes} 分',
  );

  final b = await _signUp(authRepo, 'b', clock);
  final joinedB = await b.repo.joinWithInviteCode(trip.inviteCode);
  final c = await _signUp(authRepo, 'c', clock);
  final joinedC = await c.repo.joinWithInviteCode(trip.inviteCode);
  _check(joinedB.id == trip.id && joinedC.id == trip.id, 'B 與 C 應加入同一碼');
  await _signIn(authRepo, leader.email);
  final members = await leader.repo.listMembers(trip.id);
  final ids = members.map((member) => member.userId).toSet();
  _check(ids.contains(b.uid), 'B 在名單');
  _check(ids.contains(c.uid), 'C 在名單');

  final stranger = await _signUp(authRepo, 'stranger', clock);
  try {
    await stranger.repo.remote.fetchTrip(trip.id);
    throw StateError('路人讀到了已存在的旅程');
  } on TripAccessDenied {
    // 已存在的旅程不外洩。
  }
  final missing = await stranger.repo.remote.fetchTrip('missing-trip-id');
  _check(missing == null, '不存在的旅程應讀成空，而不是拒絕');
  try {
    await stranger.repo.remote.fetchMembers(trip.id);
    throw StateError('路人列得出成員');
  } on TripAccessDenied {
    // list 仍只限成員。
  }

  await _signUp(authRepo, 'wrong', clock);
  final wrongRepo = _repository(authRepo, clock);
  try {
    await wrongRepo.joinWithInviteCode('NOSUCH01');
    throw StateError('不存在的碼不該加入');
  } on InviteNotFoundException catch (error) {
    _check(error.message == AppStrings.inviteNotFound, '找不到的訊息');
  }

  await _backdateInvite(trip.inviteCode);
  final expiredRepo = _repository(authRepo, clock);
  try {
    await expiredRepo.joinWithInviteCode(trip.inviteCode);
    throw StateError('過期的碼不該加入');
  } on InviteExpiredException catch (error) {
    _check(error.message == AppStrings.inviteExpired, '過期的訊息');
  }
  _check(
    AppStrings.inviteNotFound != AppStrings.inviteExpired &&
        AppStrings.inviteExpired != AppStrings.invitePermissionOrNetwork &&
        AppStrings.inviteNotFound != AppStrings.invitePermissionOrNetwork,
    '三種加入錯誤的文字應不同',
  );

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

  final skewClock = FixedDeviceClock(DateTime.now().toUtc());
  final skew = await _signUp(authRepo, 'skew', skewClock);
  final skewTrip = await skew.repo.createTrip(_form('時鐘團', '2030-05-01', '2030-05-02'));
  final before = (await skew.repo.listInvites(skewTrip.id)).map((invite) => invite.code).toSet();
  skewClock.current = DateTime.now().toUtc().add(const Duration(minutes: 2));
  final fast = await skew.repo.issueInviteCode(skewTrip.id);
  _codeOk(fast.code, '快 2 分鐘的碼');
  _check(await skew.repo.remote.fetchInvite(fast.code) != null, '快 2 分鐘應寫入伺服器');

  skewClock.current = DateTime.now().toUtc().add(const Duration(minutes: 10));
  final slowLogs = await _capture(() async {
    try {
      await skew.repo.issueInviteCode(skewTrip.id);
      throw StateError('快 10 分鐘不該產生邀請碼');
    } on ServerWriteException catch (error) {
      _check(error.message == AppStrings.serverWriteFailed, '發碼失敗的訊息');
    }
  });
  _check(slowLogs.contains('FirebaseException'), '發碼失敗要記下 FirebaseException');
  _check(slowLogs.contains('permission-denied'), '發碼失敗的原因應是 permission-denied');
  final after = (await skew.repo.listInvites(skewTrip.id)).map((invite) => invite.code).toSet();
  _check(after.contains(fast.code), '快 2 分鐘的碼還在');
  _check(after.difference(before).length == 1, '快 10 分鐘不能多一個碼');

  final spanClock = FixedDeviceClock(DateTime.now().toUtc());
  final spanUser = await _signUp(authRepo, 'span', spanClock);
  final spanLogs = await _capture(() async {
    try {
      await spanUser.repo.createTrip(_form('太長', '2030-01-01', '2030-03-01'));
      throw StateError('超過 30 天的旅程不該建立成功');
    } on ServerWriteException catch (error) {
      _check(error.message == AppStrings.serverWriteFailed, '旅程寫入失敗的訊息');
    }
  });
  _check(spanLogs.contains('FirebaseException'), '旅程寫入失敗要記下 FirebaseException');
  _check(spanLogs.contains('permission-denied'), '旅程寫入失敗應是 permission-denied');
  final titles = (await spanUser.repo.listMyTrips()).map((item) => item.title).toSet();
  _check(!titles.contains('太長'), '失敗的旅程不該留在手機上');
  final raw = await spanUser.store.read();
  final invites = raw['invites'];
  _check(invites == null || (invites is Map && invites.isEmpty), '失敗的旅程不該留下邀請碼');

  final notes = await _publicInvites(authRepo);
  return 'member-code-after-close=$notes';
}

Future<String> _publicInvites(FirebaseAuthRepository authRepo) async {
  final clock = FixedDeviceClock(DateTime.now().toUtc());
  final leader = await _signUp(authRepo, 'pub-leader', clock);
  final trip = await leader.repo.createTrip(_form('公開邀請', '2030-06-01', '2030-06-03'));
  final people = <_Person>[];
  for (final name in ['m1', 'm2', 'm3', 'deputy']) {
    final person = await _signUp(authRepo, name, clock);
    await person.repo.joinWithInviteCode(trip.inviteCode);
    people.add(person);
  }
  final member = people.first;
  final deputy = people.last;
  await _signIn(authRepo, member.email);
  final memberCode = await member.repo.issueInviteCode(trip.id);
  _codeOk(memberCode.code, '一般成員的碼');

  await _signIn(authRepo, leader.email);
  final roster = await leader.repo.listMembers(trip.id);
  _check(roster.length >= 5, '至少 5 人才能設副隊長，實際 ${roster.length}');
  await leader.repo.assignViceCaptain(tripId: trip.id, userId: deputy.uid);

  await _signIn(authRepo, deputy.email);
  final closed = await deputy.repo.setPublicInvite(tripId: trip.id, enabled: false);
  _check(closed.publicInvite == false, '副隊長應能關掉公開邀請');
  final deputyCode = await deputy.repo.issueInviteCode(trip.id);
  _codeOk(deputyCode.code, '副隊長在關閉後的碼');

  final outsider = await _signUp(authRepo, 'blocked', clock);
  String deniedAs;
  try {
    await outsider.repo.joinWithInviteCode(memberCode.code);
    throw StateError('關掉公開邀請後，一般成員的碼仍可加入');
  } on InviteNotFoundException {
    throw StateError('一般成員的碼不該變成找不到');
  } on TripException catch (error) {
    deniedAs = '${error.runtimeType}:${error.message}';
  }

  final leaderGuest = await _signUp(authRepo, 'leader-guest', clock);
  await _backdateInvite(trip.inviteCode, createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 50)));
  // The leader code was just moved 50 minutes into its hour, still inside 1h.
  final viaLeader = await leaderGuest.repo.joinWithInviteCode(trip.inviteCode);
  _check(viaLeader.id == trip.id, '隊長的碼在關閉後、一小時內仍可加入');

  final deputyGuest = await _signUp(authRepo, 'deputy-guest', clock);
  final viaDeputy = await deputyGuest.repo.joinWithInviteCode(deputyCode.code);
  _check(viaDeputy.id == trip.id, '副隊長的碼在關閉後仍可加入');

  await _signIn(authRepo, deputy.email);
  final reopened = await deputy.repo.setPublicInvite(tripId: trip.id, enabled: true);
  _check(reopened.publicInvite == true, '副隊長應能再打開公開邀請');
  final revived = await _signUp(authRepo, 'revived', clock);
  try {
    await revived.repo.joinWithInviteCode(memberCode.code);
    throw StateError('重新打開不該讓一般成員的舊碼復活');
  } on InviteNotFoundException {
    throw StateError('舊碼不該變成找不到');
  } on TripException {
    // 截止時間還在，舊碼仍然不能用。
  }
  return deniedAs;
}

Future<void> _backdateInvite(String code, {DateTime? createdAt}) async {
  final created = (createdAt ?? DateTime.utc(2020, 1, 1)).toUtc();
  final expires = created.add(const Duration(hours: 1));
  final url =
      'http://$_firestoreHost:$_firestorePort/v1/projects/demo-app/databases/(default)/documents/invites/$code'
      '?updateMask.fieldPaths=createdAt&updateMask.fieldPaths=expiresAt';
  final response = await web.window
      .fetch(
        url.toJS,
        web.RequestInit(
          method: 'PATCH',
          headers: {
            'Authorization': 'Bearer owner',
            'Content-Type': 'application/json',
          }.jsify()! as JSObject,
          body: jsonEncode({
            'fields': {
              'createdAt': {'timestampValue': created.toIso8601String()},
              'expiresAt': {'timestampValue': expires.toIso8601String()},
            },
          }).toJS,
        ),
      )
      .toDart;
  if (!response.ok) {
    final body = (await response.text().toDart).toDart;
    throw StateError('無法回寫邀請碼效期 HTTP ${response.status} $body');
  }
}

Future<String> _capture(Future<void> Function() body) async {
  final logs = <String>[];
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    logs.add(message ?? '');
  };
  try {
    await body();
  } finally {
    debugPrint = previous;
  }
  return logs.join('\n');
}

Future<_Person> _signUp(
  FirebaseAuthRepository authRepo,
  String name,
  DeviceClock clock,
) async {
  final email = _email(name);
  _publish('RUNNING signup $name');
  final outcome = await authRepo.signUp(
    email: email,
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
  final store = MemoryDocumentStore();
  return _Person(
    email: email,
    uid: account.id,
    name: name,
    store: store,
    repo: _repository(authRepo, clock, store: store),
  );
}

Future<void> _signIn(FirebaseAuthRepository authRepo, String email) async {
  final outcome = await authRepo.signIn(email: email, password: 'password1');
  if (outcome.failure != null || outcome.account == null) {
    throw StateError('登入失敗 ${outcome.failure?.message}');
  }
}

OfflineTripRepository _repository(
  FirebaseAuthRepository authRepo,
  DeviceClock clock, {
  String? accountId,
  MemoryDocumentStore? store,
}) {
  final auth = FirebaseAuth.instance;
  return OfflineTripRepository(
    local: TripLocalStore(store ?? MemoryDocumentStore()),
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

NewTripForm _form(String title, String start, String end) {
  return NewTripForm(
    title: title,
    startDate: start,
    endDate: end,
    timeZone: 'Asia/Taipei',
    returnDate: '',
    returnTime: '',
  );
}
