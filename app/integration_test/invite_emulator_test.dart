import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:group_trip/core/ids/id_generator.dart';
import 'package:group_trip/data/firestore_schema.dart';
import 'package:group_trip/core/persistence/json_document_store.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/features/auth/data/firebase_auth_repository.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/trip/data/firestore_paths.dart';
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
      _setStatus('RUNNING recovered invitation publication');
      await _recoveredInvitation(authRepo);
      _setStatus('RUNNING join errors');
      await _joinErrors(authRepo);
      _setStatus('RUNNING closed invite');
      await _closedPublicInvite(authRepo);
      _setStatus('RUNNING skew');
      await _clockSkew(authRepo);
      _setStatus('RUNNING request sync');
      await _requestSync(authRepo);
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

class _RecoverableConnectivity extends ConnectivityProbe {
  _RecoverableConnectivity() : super(isOnline: false);
  bool actualOnline = false;
  @override
  Future<void> refresh() async {
    isOnline = actualOnline;
  }
}

/// No production data: two Auth emulator users and the real Firestore rules.
Future<void> _recoveredInvitation(FirebaseAuthRepository authRepo) async {
  await _signUp(authRepo, '離線恢復隊長');
  final clock = FixedDeviceClock(
    DateTime.now().toUtc().subtract(const Duration(minutes: 10)),
  );
  final connectivity = _RecoverableConnectivity();
  final remote = FirestoreTripRemote(
    firestore: FirebaseFirestore.instance,
    currentUserId: () => FirebaseAuth.instance.currentUser?.uid ?? '',
  );
  final repository = OfflineTripRepository(
    local: TripLocalStore(MemoryDocumentStore()),
    remote: remote,
    currentAccount: () => authRepo.current,
    clock: clock,
    ids: RandomIdGenerator(),
    connectivity: connectivity,
  );
  final trip = await repository.createTrip(_form('離線恢復邀請'));
  final pending = (await repository.local.readInvites(trip.id)).single;
  _check(!pending.serverConfirmed, '離線碼不能視為已確認');
  _check(await remote.fetchInvite(pending.code) == null, '離線碼尚未發布');

  clock.current = DateTime.now().toUtc();
  connectivity.actualOnline = true; // The Home page has not refreshed.
  final issued = await repository.issueInviteCode(trip.id);
  _check(issued.serverConfirmed, '新碼需讀回伺服器確認');
  // #48：發碼成功後其他待上傳變更改由背景同步發布，不再擋住新碼回傳。
  // sync() 會沿用進行中的那次同步，等它完成再檢查舊碼。
  await repository.sync();
  final oldPublished = await remote.fetchInvite(pending.code);
  _check(oldPublished != null, '超過五分鐘的待上傳碼需能首次發布');
  _check(
    oldPublished!.expiresAt.isAfter(
      DateTime.now().toUtc().add(const Duration(minutes: 55)),
    ),
    '只延後尚未發布碼的首次效期',
  );
  // The document is cached now. An offline read must fail, not turn that cache
  // into a new server confirmation.
  await FirebaseFirestore.instance.disableNetwork();
  try {
    var rejectedCachedRead = false;
    try {
      await remote.fetchInvite(issued.code);
    } on TripException {
      rejectedCachedRead = true;
    }
    _check(rejectedCachedRead, '離線快取不能充當伺服器確認');
  } finally {
    await FirebaseFirestore.instance.enableNetwork();
  }
  await authRepo.signOut();

  await _signUp(authRepo, '離線恢復加入者');
  final joiner = _repository(
    authRepo,
    FixedDeviceClock(DateTime.now().toUtc()),
  );
  final fullWidth = String.fromCharCodes(
    issued.code.toLowerCase().runes.map((rune) => rune + 0xfee0),
  );
  final joined = await joiner.joinWithInviteCode('　$fullWidth　');
  _check(joined.id == trip.id, '另一位使用者可用新碼加入');
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

Future<void> _closedPublicInvite(FirebaseAuthRepository authRepo) async {
  final clock = FixedDeviceClock(DateTime.now().toUtc());
  final captain = await _signUp(authRepo, '關閉隊長');
  final captainRepo = _repository(authRepo, clock);
  final trip = await captainRepo.createTrip(_form('關閉團'));
  final captainCode = trip.inviteCode;
  _check(captainCode.isNotEmpty, '隊長應有邀請碼');

  await authRepo.signOut();
  await _signUp(authRepo, '發碼成員');
  final memberRepo = _repository(authRepo, clock);
  await memberRepo.joinWithInviteCode(captainCode);
  final memberCode = await memberRepo.issueInviteCode(trip.id);
  _check(memberCode.issuerRole == MemberRole.member, '一般成員產生的碼');

  await authRepo.signOut();
  final vice = await _signUp(authRepo, '副隊長');
  final viceRepo = _repository(authRepo, clock);
  await viceRepo.joinWithInviteCode(captainCode);

  await authRepo.signOut();
  final captainSignIn = await authRepo.signIn(
    email: captain.email,
    password: 'password1',
  );
  if (captainSignIn.failure != null || captainSignIn.account == null) {
    throw StateError('隊長重新登入失敗 ${captainSignIn.failure?.message}');
  }
  await FirebaseFirestore.instance
      .collection(FirestorePaths.trips)
      .doc(trip.id)
      .collection(FirestorePaths.members)
      .doc(vice.id)
      .update({FirestoreSchema.role: FirestoreSchema.roleDeputy});

  await authRepo.signOut();
  final viceSignIn = await authRepo.signIn(
    email: vice.email,
    password: 'password1',
  );
  if (viceSignIn.failure != null || viceSignIn.account == null) {
    throw StateError('副隊長重新登入失敗 ${viceSignIn.failure?.message}');
  }
  final viceCode = await viceRepo.issueInviteCode(trip.id);
  _check(viceCode.issuerRole == MemberRole.viceCaptain, '副隊長產生的碼');

  await authRepo.signOut();
  final closeSignIn = await authRepo.signIn(
    email: captain.email,
    password: 'password1',
  );
  if (closeSignIn.failure != null || closeSignIn.account == null) {
    throw StateError('隊長關邀請前登入失敗 ${closeSignIn.failure?.message}');
  }
  final closed = await captainRepo.setPublicInvite(
    tripId: trip.id,
    enabled: false,
  );
  _check(!closed.publicInvite, '公開邀請應關閉');
  await authRepo.signOut();

  await _signUp(authRepo, '用成員碼');
  final memberGuest = _repository(authRepo, clock);
  try {
    await memberGuest.joinWithInviteCode(memberCode.code);
    throw StateError('公開邀請關閉後，一般成員的碼不該加入');
  } on InviteClosedException catch (error) {
    _check(
      error.message == AppStrings.inviteClosedByPublicInvite,
      '公開邀請已關閉的訊息',
    );
  }
  await authRepo.signOut();

  await _signUp(authRepo, '用隊長碼');
  final captainGuest = _repository(authRepo, clock);
  final viaCaptain = await captainGuest.joinWithInviteCode(captainCode);
  _check(viaCaptain.id == trip.id, '隊長的碼仍可加入');
  await authRepo.signOut();

  await _signUp(authRepo, '用副隊長碼');
  final viceGuest = _repository(authRepo, clock);
  final viaVice = await viceGuest.joinWithInviteCode(viceCode.code);
  _check(viaVice.id == trip.id, '副隊長的碼仍可加入');
  await authRepo.signOut();

  await _signUp(authRepo, '寫入斷線');
  final offlineGuest = _repository(
    authRepo,
    clock,
    remote: _MemberWriteOfflineRemote(
      firestore: FirebaseFirestore.instance,
      currentUserId: () => FirebaseAuth.instance.currentUser?.uid ?? '',
    ),
  );
  final logs = <String>[];
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    logs.add(message ?? '');
  };
  try {
    await offlineGuest.joinWithInviteCode(memberCode.code);
    throw StateError('成員寫入斷線不該加入成功');
  } on InvitePermissionException catch (error) {
    _check(error.message == AppStrings.invitePermissionOrNetwork, '斷線仍是原本的訊息');
    _check(
      error.message != AppStrings.inviteClosedByPublicInvite,
      '斷線不能顯示公開邀請已關閉',
    );
  } on InviteClosedException catch (error) {
    throw StateError('斷線不該顯示公開邀請已關閉 ${error.message}');
  } finally {
    debugPrint = previous;
  }
  _check(
    logs.join('\n').contains('code=unavailable'),
    '成員寫入要記下 unavailable，實際 ${logs.join(' | ')}',
  );
  await authRepo.signOut();
}

/// 修改申請的同步邊界：離線時還沒上傳就被決定、重送 pending、伺服器已有人決定。
/// 核准一律走 approveRequest，旅程與申請同一個 batch 寫入。
Future<void> _requestSync(FirebaseAuthRepository authRepo) async {
  final clock = FixedDeviceClock(DateTime.now().toUtc());
  final leader = await _signUp(authRepo, '申請隊長');
  final repo = _repository(authRepo, clock);
  final trip = await repo.createTrip(_form('申請團'));
  final remote = repo.remote;
  final now = DateTime.now().toUtc();
  DateTime daysAhead(int days) => DateTime.fromMillisecondsSinceEpoch(
    now.add(Duration(days: days)).millisecondsSinceEpoch,
    isUtc: true,
  );

  ModificationRequest request(
    String id,
    RequestStatus status,
    DateTime proposed,
  ) {
    final decided = status != RequestStatus.pending;
    return ModificationRequest(
      id: id,
      tripId: trip.id,
      requesterId: leader.id,
      requesterName: leader.displayName,
      type: ModificationType.expectedReturnTime,
      proposedExpectedReturnAt: proposed,
      status: status,
      createdAt: now,
      expiresAt: null,
      resolvedAt: decided ? now : null,
      resolvedBy: decided ? leader.id : null,
    );
  }

  DocumentReference<Map<String, dynamic>> tripDoc() =>
      FirebaseFirestore.instance.collection(FirestorePaths.trips).doc(trip.id);

  Future<String?> serverStatus(String id) async {
    final snap = await tripDoc()
        .collection(FirestorePaths.requests)
        .doc(id)
        .get(const GetOptions(source: Source.server));
    return snap.data()?[FirestoreSchema.status] as String?;
  }

  Future<DateTime?> serverReturnAt() async {
    final snap = await tripDoc().get(const GetOptions(source: Source.server));
    final value = snap.data()?[FirestoreSchema.expectedReturnAt];
    return value is Timestamp ? value.toDate().toUtc() : null;
  }

  // 1. 還沒上傳就被核准：先建立 pending，再用同一個 batch 寫旅程與核准，
  //    規則的 getAfter 核對旅程上的值等於申請內容。
  final first = daysAhead(30);
  await remote.approveRequest(
    request('offline-approve', RequestStatus.approved, first),
  );
  _check(
    await serverStatus('offline-approve') == RequestStatus.approved.name,
    '還沒上傳就核准的申請，伺服器上要是 approved',
  );
  _check(
    (await serverReturnAt())?.isAtSameMomentAs(first) ?? false,
    '核准後伺服器旅程的預計回程時間要是申請的值',
  );

  // 2. 本機仍是 pending、伺服器已有文件：重送不能失敗。
  final second = daysAhead(31);
  await remote.upsertRequest(
    request('resend-pending', RequestStatus.pending, second),
  );
  await remote.upsertRequest(
    request('resend-pending', RequestStatus.pending, second),
  );
  _check(
    await serverStatus('resend-pending') == RequestStatus.pending.name,
    '重送 pending 後仍是 pending',
  );

  // 3. 伺服器已經拒絕，這台手機晚一步核准：丟出已處理，伺服器旅程不變。
  await remote.upsertRequest(
    request('resend-pending', RequestStatus.rejected, second),
  );
  try {
    await remote.approveRequest(
      request('resend-pending', RequestStatus.approved, second),
    );
    throw StateError('伺服器已拒絕的申請不該核准成功');
  } on RequestHandledException {
    // 預期。
  }
  _check(
    await serverStatus('resend-pending') == RequestStatus.rejected.name,
    '伺服器已拒絕的申請要維持 rejected',
  );
  _check(
    (await serverReturnAt())?.isAtSameMomentAs(first) ?? false,
    '晚一步的核准不能改動伺服器旅程',
  );
  // 同步路徑（upsertRequest 帶 approved）遇到已決定的申請也不能卡住。
  await remote.upsertRequest(
    request('resend-pending', RequestStatus.approved, second),
  );
  await authRepo.signOut();
}

Future<void> _clockSkew(FirebaseAuthRepository authRepo) async {
  final clock = FixedDeviceClock(DateTime.now().toUtc());
  await _signUp(authRepo, '時鐘');
  final repo = _repository(authRepo, clock);
  final trip = await repo.createTrip(_form('時鐘團'));
  final before = (await repo.listInvites(trip.id))
      .map((invite) => invite.code)
      .toSet();

  clock.current = DateTime.now().toUtc().add(const Duration(minutes: 2));
  final issued = await repo.issueInviteCode(trip.id);
  _check(issued.code.isNotEmpty, '快 2 分鐘仍應產生邀請碼');
  _check(
    (await repo.listInvites(trip.id))
        .any((invite) => invite.code == issued.code),
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
  _check(
    logs.join('\n').contains('permission-denied'),
    '要記下 FirebaseException',
  );
  final after = (await repo.listInvites(trip.id))
      .map((invite) => invite.code)
      .toSet();
  _check(after.contains(issued.code), '原本快 2 分鐘的碼還在');
  _check(after.difference(before).length == 1, '快 10 分鐘不能多一個碼');
  await authRepo.signOut();
}

int _serial = 0;

String _email(String label) {
  _serial += 1;
  return '$label-$_serial@example.com';
}

Future<UserAccount> _signUp(
  FirebaseAuthRepository authRepo,
  String name,
) async {
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
  FirestoreTripRemote? remote,
}) {
  final auth = FirebaseAuth.instance;
  return OfflineTripRepository(
    local: TripLocalStore(MemoryDocumentStore()),
    remote:
        remote ??
        FirestoreTripRemote(
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

/// 網頁版 Firestore 的 `set` 在斷線時會排隊、不會拒絕。
/// 這裡仍對成員文件呼叫 `set`，再向伺服器讀一次，取得真實的 `unavailable`。
class _MemberWriteOfflineRemote extends FirestoreTripRemote {
  _MemberWriteOfflineRemote({required super.currentUserId, super.firestore});

  @override
  Future<void> commitJoinMember(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) async {
    final firestore = FirebaseFirestore.instance;
    await firestore.disableNetwork();
    final pending = super.commitJoinMember(ref, data);
    pending.then((_) {}, onError: (Object _) {});
    try {
      await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      throw StateError('斷線時不該從伺服器讀到這次要寫的成員文件');
    } on TimeoutException {
      throw StateError('斷線讀取逾時，沒有拿到 unavailable');
    } on FirebaseException catch (error) {
      if (error.code != 'unavailable') {
        throw StateError(
          '成員寫入遇到的網路錯誤應為 unavailable，實際 ${error.code} ${error.message}',
        );
      }
      rethrow;
    } finally {
      await firestore.enableNetwork();
    }
  }
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
