import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/features/home/home_page.dart';
import 'package:group_trip/features/trip/data/firestore_trip_remote.dart';
import 'package:group_trip/features/trip/data/memory_trip_remote.dart';
import 'package:group_trip/features/trip/data/offline_trip_repository.dart';
import 'package:group_trip/features/trip/data/trip_local_store.dart';
import 'package:group_trip/core/persistence/json_document_store.dart';
import 'package:group_trip/features/trip/domain/trip_codec.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/features/trip/presentation/create_trip_page.dart';
import 'package:group_trip/features/trip/presentation/join_trip_page.dart';
import 'package:group_trip/features/trip/presentation/trip_detail_page.dart';
import 'package:group_trip/l10n/app_strings.dart';

import 'support/harness.dart';

const _timeoutMessage = '網路不穩，旅程尚未寫入伺服器，請稍後再試';
const _pendingMessage = '尚未同步，別人暫時無法加入';
const _form = NewTripForm(
  title: '驗收旅程',
  startDate: '2026-11-01',
  endDate: '2026-11-05',
  timeZone: 'Asia/Taipei',
  returnDate: '',
  returnTime: '',
);

Future<void> _signIn(TestWorld world) => world.auth.signUp(
  email: 'host@example.com',
  password: 'password1',
  displayName: '隊長',
  birthday: '2000-01-01',
  birthdayConsent: true,
  today: world.clock.current,
);

void _largeScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  for (final phase in ['旅程', '成員', '邀請碼']) {
    testWidgets('$phase 寫入卡住：第 15 秒停止等待、顯示錯誤並丟棄本機資料', (tester) async {
      _largeScreen(tester);
      late _ControlledRemote remote;
      final world = TestWorld(
        remoteFactory: (database, user) =>
            remote = _ControlledRemote(database: database, currentUserId: user)
              ..blockedPhase = phase,
      );
      await _signIn(world);
      await tester.pumpWidget(
        wrapPage(
          world.deps,
          const CreateTripPage(initialTimeZone: 'Asia/Taipei'),
        ),
      );
      await enterLabeled(tester, AppStrings.tripTitle, _form.title);
      await enterLabeled(tester, AppStrings.startDate, _form.startDate);
      await enterLabeled(tester, AppStrings.endDate, _form.endDate);
      final submit = find.widgetWithText(
        FilledButton,
        AppStrings.submitCreateTrip,
      );
      await tester.tap(submit);
      await tester.pump();
      expect(remote.blockedTripId, isNotNull);
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);

      // WidgetTester 的虛擬時間；測試不會真的等待 15 秒。
      await tester.pump(const Duration(milliseconds: 14999));
      expect(find.text(_timeoutMessage), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text(_timeoutMessage), findsOneWidget);
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      expect(find.byType(TripDetailPage), findsNothing);
      expect(find.byKey(const Key('invite-code')), findsNothing);
      final tripId = remote.blockedTripId!;
      expect(await world.trips.local.readAllTrips(), isEmpty);
      expect(await world.trips.local.readMembers(tripId), isEmpty);
      expect(await world.trips.local.readInvites(tripId), isEmpty);
      expect(await world.trips.local.readQueue(), isEmpty);

      // 遲到的成功不能重新建立本機邀請，也不能繼續送剩餘的建立步驟。
      final writesAtTimeout = List<String>.of(remote.writes);
      remote.release.complete();
      await tester.pump();
      expect(remote.writes, writesAtTimeout);
      await world.trips.listMyTrips();
      expect(await world.trips.local.readAllTrips(), isEmpty);
      expect(await world.trips.local.readInvites(tripId), isEmpty);
      expect(await world.trips.local.readQueue(), isEmpty);
    });
  }

  testWidgets('建立旅程的多筆寫入共用 15 秒，不在進入下一階段時重新計時', (tester) async {
    late _ControlledRemote remote;
    final world = TestWorld(
      remoteFactory: (database, user) =>
          remote = _ControlledRemote(database: database, currentUserId: user)
            ..tripDelay = const Duration(seconds: 10)
            ..blockedPhase = '成員',
    );
    await _signIn(world);
    Object? failure;
    final result = world.trips
        .createTrip(_form)
        .then<void>(
          (_) => fail('伺服器未確認成員時不該回報建立成功'),
          onError: (Object error) => failure = error,
        );
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(remote.writes, ['旅程', '成員']);
    expect(failure, isNull);
    await tester.pump(const Duration(seconds: 5));
    await result;
    expect(failure, isA<ServerWriteException>());
    expect((failure as ServerWriteException).message, _timeoutMessage);
    expect(await world.trips.local.readAllTrips(), isEmpty);
    expect(await world.trips.local.readInvites(remote.blockedTripId!), isEmpty);
    expect(await world.trips.local.readQueue(), isEmpty);
    remote.release.complete();
    await tester.pump();
    expect(remote.writes, ['旅程', '成員']);
    await world.trips.listMyTrips();
    expect(await world.trips.local.readAllTrips(), isEmpty);
  });

  testWidgets('產生新碼逾時：保留原碼、丟棄新碼，遲到回應也不能讓新碼復活', (tester) async {
    _largeScreen(tester);
    late _ControlledRemote remote;
    final world = TestWorld(
      remoteFactory: (database, user) =>
          remote = _ControlledRemote(database: database, currentUserId: user),
    );
    await _signIn(world);
    final trip = await world.trips.createTrip(_form);
    await tester.pumpWidget(
      wrapPage(world.deps, TripDetailPage(tripId: trip.id)),
    );
    await tester.pumpAndSettle();
    remote.blockedPhase = '邀請碼';
    await tester.tap(find.byKey(const Key('issue-invite')));
    await tester.pump();
    final newCode = remote.blockedCode!;
    await tester.pump(const Duration(seconds: 15));
    expect(find.text(_timeoutMessage), findsOneWidget);
    expect(find.text(AppStrings.copyInviteCode(newCode)), findsNothing);
    expect(
      find.text(AppStrings.copyInviteCode(trip.inviteCode)),
      findsOneWidget,
    );
    expect(await world.trips.local.readInvite(newCode), isNull);
    expect(await world.trips.local.readQueue(), isEmpty);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('issue-invite')))
          .onPressed,
      isNotNull,
    );
    remote.release.complete();
    await tester.pump();
    await world.trips.listMyTrips();
    expect(await world.trips.local.readInvite(newCode), isNull);
  });

  testWidgets('離線旅程上線發碼：讀成員與建立旅程已用 13 秒，成員卡住仍在第 15 秒失敗', (tester) async {
    late _ControlledRemote remote;
    final world = TestWorld(
      online: false,
      remoteFactory: (database, user) =>
          remote = _ControlledRemote(database: database, currentUserId: user),
    );
    await _signIn(world);
    final trip = await world.trips.createTrip(_form);
    world.connectivity.isOnline = true;
    remote
      ..membersDelay = const Duration(seconds: 3)
      ..tripDelay = const Duration(seconds: 10)
      ..blockedPhase = '成員';
    Object? failure;
    final result = world.trips
        .issueInviteCode(trip.id)
        .then<void>(
          (_) => fail('成員寫入尚未確認，不該產生可分享的新碼'),
          onError: (Object error) => failure = error,
        );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(remote.writes, ['旅程']);
    await tester.pump(const Duration(seconds: 10));
    expect(remote.writes, ['旅程', '成員']);
    expect(failure, isNull);
    await tester.pump(const Duration(seconds: 2));
    await result;
    expect(failure, isA<ServerWriteException>());
    expect((failure as ServerWriteException).message, _timeoutMessage);
    expect((await world.trips.local.readInvites(trip.id)).map((i) => i.code), [
      trip.inviteCode,
    ]);
    expect(world.database.invites, isEmpty);
    remote.release.complete();
    await tester.pump();
    expect(remote.writes, ['旅程', '成員']);
  });

  test('丟棄清單存於手機，重新開啟本機儲存後仍擋住旅程與邀請碼', () async {
    final world = TestWorld(online: false);
    await _signIn(world);
    final trip = await world.trips.createTrip(_form);
    final invite = (await world.trips.local.readInvites(trip.id)).single;
    final documents = MemoryDocumentStore();
    final first = TripLocalStore(documents);
    await first.saveTrip(trip);
    await first.saveInvite(invite);
    await first.discardTrip(trip.id);
    final reopened = TripLocalStore(documents);
    await reopened.saveTrip(trip);
    await reopened.saveInvite(invite.withServerConfirmation(true));
    expect(await reopened.readAllTrips(), isEmpty);
    expect(await reopened.readInvites(trip.id), isEmpty);

    final another = InviteRecord(
      code: 'DISCARD1',
      tripId: 'other-trip',
      createdBy: 'host',
      createdAt: invite.createdAt,
      expiresAt: invite.expiresAt,
    );
    await first.saveInvite(another);
    await first.deleteInvite(another.code);
    await reopened.saveInvite(another.withServerConfirmation(true));
    expect(await reopened.readInvite(another.code), isNull);
  });

  testWidgets('新碼已確認時立即回傳，不等待成功後的背景同步', (tester) async {
    late _ObservedRepository repository;
    final world = TestWorld(
      repositoryFactory: (base) => repository = _ObservedRepository(base),
    );
    await _signIn(world);
    final trip = await world.trips.createTrip(_form);
    final previousSyncCalls = repository.syncCalls;
    final gate = Completer<void>();
    repository.syncGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    InviteRecord? issued;
    final result = world.trips.issueInviteCode(trip.id).then((invite) {
      issued = invite;
    });
    await tester.pump();
    expect(repository.syncCalls, previousSyncCalls + 1);
    expect(issued, isNotNull);
    expect(issued!.serverConfirmed, isTrue);
    expect(world.database.invites.containsKey(issued!.code), isTrue);
    expect(gate.isCompleted, isFalse);
    gate.complete();
    await result;
    await tester.pump();
  });

  testWidgets('邀請確認只讀待同步碼、不跑完整同步，離線不輪詢且依 2→4→8→60 秒退避', (tester) async {
    _largeScreen(tester);
    late _ControlledRemote remote;
    late _ObservedRepository repository;
    final world = TestWorld(
      online: false,
      remoteFactory: (database, user) =>
          remote = _ControlledRemote(database: database, currentUserId: user),
      repositoryFactory: (base) => repository = _ObservedRepository(base),
    );
    await _signIn(world);
    final trip = await world.trips.createTrip(_form);
    final pending = (await world.trips.local.readInvites(trip.id)).single;
    await world.trips.local.saveInvite(
      InviteRecord(
        code: 'CONFIRM1',
        tripId: trip.id,
        createdBy: pending.createdBy,
        createdAt: pending.createdAt,
        expiresAt: pending.expiresAt,
        serverConfirmed: true,
      ),
    );
    await tester.pumpWidget(
      wrapPage(world.deps, TripDetailPage(tripId: trip.id)),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 10));
    expect(repository.pendingChecks, 0);
    expect(repository.syncCalls, 0);
    expect(remote.inviteReads, isEmpty);

    world.connectivity.isOnline = true;
    var checks = 0;
    for (final seconds in [2, 4, 8, 16, 32, 60, 60]) {
      await tester.pump(Duration(milliseconds: seconds * 1000 - 1));
      expect(repository.pendingChecks, checks);
      await tester.pump(const Duration(milliseconds: 1));
      checks++;
      expect(repository.pendingChecks, checks);
      expect(remote.inviteReads, List.filled(checks, trip.inviteCode));
      expect(repository.syncCalls, 0);
    }
    world.connectivity.isOnline = false;
    await tester.pump(const Duration(minutes: 10));
    expect(repository.pendingChecks, checks);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('輪詢讀快取失敗後仍可於下一輪重試，不會卡住 checking 狀態', (tester) async {
    _largeScreen(tester);
    late _ObservedRepository repository;
    final world = TestWorld(
      online: false,
      repositoryFactory: (base) => repository = _ObservedRepository(base),
    );
    await _signIn(world);
    final trip = await world.trips.createTrip(_form);
    await tester.pumpWidget(
      wrapPage(world.deps, TripDetailPage(tripId: trip.id)),
    );
    await tester.pumpAndSettle();
    repository.cacheFailures = 1;
    world.connectivity.isOnline = true;
    await tester.pump(const Duration(seconds: 2));
    expect(repository.pendingChecks, 1);
    await tester.pump(const Duration(seconds: 4));
    expect(repository.pendingChecks, 2);
    expect(repository.syncCalls, 0);
    expect(tester.takeException(), isNull);
    world.connectivity.isOnline = false;
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('一般同步申請逾時使用一般 TripException，保留佇列且不顯示建立旅程錯誤', (tester) async {
    late _ControlledRemote remote;
    final world = TestWorld(
      remoteFactory: (database, user) =>
          remote = _ControlledRemote(database: database, currentUserId: user),
    );
    await _signIn(world);
    final trip = await world.trips.createTrip(_form);
    final request = ModificationRequest(
      id: 'pending',
      tripId: trip.id,
      requesterId: world.auth.current!.id,
      requesterName: '隊長',
      type: ModificationType.expectedReturnTime,
      proposedExpectedReturnAt: world.clock.current.add(
        const Duration(days: 1),
      ),
      status: RequestStatus.pending,
      createdAt: world.clock.current,
      expiresAt: null,
    );
    await world.trips.local.saveRequest(request);
    await world.trips.local.enqueue(
      SyncOp(
        type: SyncOpType.upsertRequest,
        tripId: trip.id,
        entityId: request.id,
      ),
    );
    remote.blockedPhase = '申請';
    Object? failure;
    final syncing = world.trips.sync().then<void>(
      (_) => fail('尚未確認寫入不該回報同步成功'),
      onError: (Object error) => failure = error,
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 15));
    await syncing;
    expect(failure, isA<TripException>());
    expect(failure, isNot(isA<ServerWriteException>()));
    expect((failure as TripException).message, AppStrings.syncTimedOut);
    expect((failure as TripException).message, isNot(_timeoutMessage));
    expect(await world.trips.local.readQueue(), hasLength(1));
    remote.release.complete();
    await tester.pump();
  });

  for (final issuing in [false, true]) {
    testWidgets('伺服器明確拒絕${issuing ? '新碼' : '建立旅程'}仍顯示 serverWriteFailed', (
      tester,
    ) async {
      _largeScreen(tester);
      late _ControlledRemote remote;
      final world = TestWorld(
        remoteFactory: (database, user) =>
            remote = _ControlledRemote(database: database, currentUserId: user),
      );
      await _signIn(world);
      if (issuing) {
        final trip = await world.trips.createTrip(_form);
        await tester.pumpWidget(
          wrapPage(world.deps, TripDetailPage(tripId: trip.id)),
        );
        await tester.pumpAndSettle();
        remote.rejectWrites = true;
        await tester.tap(find.byKey(const Key('issue-invite')));
      } else {
        remote.rejectWrites = true;
        await tester.pumpWidget(
          wrapPage(
            world.deps,
            const CreateTripPage(initialTimeZone: 'Asia/Taipei'),
          ),
        );
        await enterLabeled(tester, AppStrings.tripTitle, _form.title);
        await enterLabeled(tester, AppStrings.startDate, _form.startDate);
        await enterLabeled(tester, AppStrings.endDate, _form.endDate);
        await tester.tap(
          find.widgetWithText(FilledButton, AppStrings.submitCreateTrip),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.serverWriteFailed), findsOneWidget);
      expect(find.text(_timeoutMessage), findsNothing);
      expect(await world.trips.local.readQueue(), isEmpty);
    });
  }

  testWidgets('離線邀請不能複製或分享；連線同步後自動解除提示並恢復複製與分享', (tester) async {
    _largeScreen(tester);
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    late _ControlledRemote remote;
    final world = TestWorld(
      online: false,
      firebaseConfigured: true,
      remoteFactory: (database, user) =>
          remote = _ControlledRemote(database: database, currentUserId: user),
    );
    await _signIn(world);
    final trip = await world.trips.createTrip(_form);
    await tester.pumpWidget(wrapPage(world.deps, const HomePage()));
    await tester.pumpAndSettle();
    expect(find.text(_pendingMessage), findsOneWidget);
    // 看板可以分享其他資訊，但不能夾帶尚未同步的邀請碼。
    await tester.tap(find.byKey(const Key('share-board')));
    await tester.pumpAndSettle();
    expect(world.share.shared.single, isNot(contains(trip.inviteCode)));
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, AppStrings.boardInviteFriends),
        matching: find.byIcon(Icons.share_outlined),
      ),
      findsNothing,
    );

    await tester.tap(find.text(AppStrings.boardInviteFriends));
    await tester.pumpAndSettle();
    expect(find.text(_pendingMessage), findsOneWidget);
    expect(find.text(AppStrings.copyInviteCode(trip.inviteCode)), findsNothing);
    expect(find.byKey(const Key('invite-code')), findsNothing);
    expect(world.database.invites, isEmpty);

    remote.blockedPhase = '邀請碼';
    world.connectivity.isOnline = true;
    // 由其他同步入口送出；畫面輪詢本身只能確認碼，不能執行完整同步。
    final syncing = world.trips.sync();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(remote.blockedCode, trip.inviteCode);
    expect(find.text(_pendingMessage), findsOneWidget);
    expect(find.text(AppStrings.copyInviteCode(trip.inviteCode)), findsNothing);
    // 網路恢復不等於伺服器已確認；等待待寫入完成才解除封鎖。
    remote.release.complete();
    await syncing;
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text(_pendingMessage), findsNothing);
    final copy = find.text(AppStrings.copyInviteCode(trip.inviteCode));
    expect(copy, findsOneWidget);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(clipboardText, trip.inviteCode);
    expect(find.text(AppStrings.copiedInvite), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.boardInviteFriends));
    await tester.pumpAndSettle();
    expect(world.share.shared.last, contains(trip.inviteCode));
  });

  for (final (error, message) in [
    (InviteNotFoundException(), '找不到這個邀請碼。如果剛建立，請對方確認已連上網路'),
    (InvitePermissionException(), '沒有權限或網路中斷，無法加入旅程'),
    (InviteClosedException(), '這個邀請碼已失效。公開邀請關閉過，一般成員在那之前產生的邀請碼不能再使用'),
  ]) {
    testWidgets('加入失敗顯示正確訊息：${error.runtimeType}', (tester) async {
      final world = TestWorld(
        firebaseConfigured: true,
        remoteFactory: (database, user) =>
            _ControlledRemote(database: database, currentUserId: user)
              ..joinError = error,
      );
      await _signIn(world);
      await tester.pumpWidget(
        wrapPage(world.deps, const JoinTripPage(initialCode: 'ABCD1234')),
      );
      await tester.tap(
        find.widgetWithText(FilledButton, AppStrings.submitJoin),
      );
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget);
      expect(find.byType(TripDetailPage), findsNothing);
      expect(await world.trips.local.readAllTrips(), isEmpty);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, AppStrings.submitJoin),
            )
            .onPressed,
        isNotNull,
      );
    });
  }

  for (final fromCache in [false, true]) {
    test(
      'Firestore 有文件但 hasPendingWrites=true 時不能視為可用邀請（isFromCache=$fromCache）',
      () async {
        final snapshot = _Snapshot(fromCache: fromCache);
        final remote = FirestoreTripRemote(
          currentUserId: () => 'host',
          firestore: _Firestore(snapshot),
        );
        await expectLater(
          remote.fetchInvite('ABCD1234'),
          throwsA(isA<InvitePermissionException>()),
        );
        snapshot.pending = false;
        if (fromCache) {
          await expectLater(
            remote.fetchInvite('ABCD1234'),
            throwsA(isA<InvitePermissionException>()),
          );
        } else {
          expect((await remote.fetchInvite('ABCD1234'))!.code, 'ABCD1234');
        }
      },
    );
  }
}

class _ControlledRemote extends MemoryTripRemote {
  _ControlledRemote({required super.database, required super.currentUserId});
  String? blockedPhase;
  Duration tripDelay = Duration.zero;
  Duration membersDelay = Duration.zero;
  bool rejectWrites = false;
  final inviteReads = <String>[];
  String? blockedTripId;
  String? blockedCode;
  TripException? joinError;
  final release = Completer<void>();
  final writes = <String>[];

  Future<void> _write(String phase, String tripId) async {
    writes.add(phase);
    if (rejectWrites) throw TripAccessDenied();
    if (phase == '旅程' && tripDelay > Duration.zero) {
      await Future<void>.delayed(tripDelay);
    }
    if (blockedPhase != phase) return;
    blockedTripId = tripId;
    await release.future;
  }

  @override
  Future<void> upsertTrip(Trip trip) async {
    await _write('旅程', trip.id);
    await super.upsertTrip(trip);
  }

  @override
  Future<void> upsertMember(TripMember member) async {
    await _write('成員', member.tripId);
    await super.upsertMember(member);
  }

  @override
  Future<void> upsertInvite(InviteRecord invite) async {
    blockedCode = invite.code;
    await _write('邀請碼', invite.tripId);
    await super.upsertInvite(invite);
  }

  @override
  Future<List<TripMember>> fetchMembers(String tripId) async {
    if (membersDelay > Duration.zero) {
      await Future<void>.delayed(membersDelay);
    }
    return super.fetchMembers(tripId);
  }

  @override
  Future<InviteRecord?> fetchInvite(String code) async {
    inviteReads.add(code);
    return super.fetchInvite(code);
  }

  @override
  Future<void> upsertRequest(ModificationRequest request) async {
    await _write('申請', request.tripId);
    await super.upsertRequest(request);
  }

  @override
  Future<Trip> join({required String code, required TripMember member}) async {
    if (joinError != null) throw joinError!;
    return super.join(code: code, member: member);
  }
}

class _ObservedRepository extends OfflineTripRepository {
  _ObservedRepository(OfflineTripRepository base)
    : super(
        local: base.local,
        remote: base.remote,
        currentAccount: base.currentAccount,
        clock: base.clock,
        ids: base.ids,
        connectivity: base.connectivity,
        serverWriteTimeout: base.serverWriteTimeout,
      );
  int syncCalls = 0;
  Completer<void>? syncGate;
  int pendingChecks = 0;
  int cacheFailures = 0;

  @override
  Future<void> sync() {
    syncCalls++;
    return syncGate?.future ?? super.sync();
  }

  @override
  Future<void> refreshPendingInvites(String tripId) {
    pendingChecks++;
    return super.refreshPendingInvites(tripId);
  }

  @override
  Future<List<InviteRecord>> readCachedInvites(String tripId) {
    if (cacheFailures > 0) {
      cacheFailures--;
      throw TripException('快取暫時讀取失敗');
    }
    return super.readCachedInvites(tripId);
  }
}

// 只替代 Firestore 的 I/O 邊界；資料解析與 metadata 判斷跑正式 remote。
class _Firestore implements FirebaseFirestore {
  _Firestore(this.snapshot);
  final _Snapshot snapshot;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(snapshot);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// 測試替身只實作本案例需要的 Firestore I/O。
// ignore: subtype_of_sealed_class
class _Collection implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.snapshot);
  final _Snapshot snapshot;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) =>
      _Document(snapshot);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Document implements DocumentReference<Map<String, dynamic>> {
  _Document(this.snapshot);
  final _Snapshot snapshot;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([
    GetOptions? options,
  ]) async {
    expect(options?.source, Source.server);
    return snapshot;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
class _Snapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot({required this.fromCache});
  final bool fromCache;
  bool pending = true;
  @override
  bool get exists => true;
  @override
  SnapshotMetadata get metadata => _Metadata(pending, fromCache);
  @override
  Map<String, dynamic> data() => TripCodec.inviteToMap(
    InviteRecord(
      code: 'ABCD1234',
      tripId: 'trip',
      createdBy: 'host',
      createdAt: DateTime.utc(2026, 11, 1),
      expiresAt: DateTime.utc(2026, 11, 1, 1),
    ),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Metadata implements SnapshotMetadata {
  _Metadata(this.hasPendingWrites, this.isFromCache);
  @override
  final bool hasPendingWrites;
  @override
  final bool isFromCache;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
