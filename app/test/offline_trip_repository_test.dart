import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/core/ids/id_generator.dart';
import 'package:group_trip/core/persistence/json_document_store.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/trip/data/memory_trip_remote.dart';
import 'package:group_trip/features/trip/data/offline_trip_repository.dart';
import 'package:group_trip/features/trip/data/trip_local_store.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/l10n/app_strings.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'support/harness.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  UserAccount person(String id, String name, {String birthday = '2000-01-01'}) {
    return UserAccount(
      id: id,
      email: '$id@example.com',
      displayName: name,
      birthday: birthday,
      consentDecided: true,
      analyticsConsent: false,
      crashlyticsConsent: false,
    );
  }

  NewTripForm sampleForm({
    String returnDate = '2026-11-05',
    String returnTime = '18:00',
  }) {
    return NewTripForm(
      title: '京都自由行',
      startDate: '2026-11-01',
      endDate: '2026-11-05',
      timeZone: 'Asia/Taipei',
      returnDate: returnDate,
      returnTime: returnTime,
    );
  }

  test('斷網可以建立旅程並讀回來，恢復連線後另一台手機看得到', () async {
    final database = MemoryTripDatabase()
      ..clock = DateTime.utc(2026, 10, 26, 1);
    final connectivity = ConnectivityProbe(isOnline: false);
    final captain = person('captain', '隊長小美');
    final captainClock = FixedDeviceClock(DateTime.utc(2026, 10, 26, 1));
    final captainRepo = OfflineTripRepository(
      local: TripLocalStore(MemoryDocumentStore()),
      remote: MemoryTripRemote(
        database: database,
        currentUserId: () => captain.id,
      ),
      currentAccount: () => captain,
      clock: captainClock,
      ids: SequentialId(),
      connectivity: connectivity,
    );

    final trip = await captainRepo.createTrip(sampleForm());
    expect(trip.inviteCode, isNotEmpty);
    expect(trip.endDate, '2026-11-05');
    expect(trip.expectedReturnAt, isNotNull);
    expect(database.trips, isEmpty);
    final offlineRead = await captainRepo.getTrip(trip.id);
    expect(offlineRead.title, '京都自由行');
    expect(
      (await captainRepo.listMembers(trip.id)).single.role,
      MemberRole.captain,
    );
    expect((await captainRepo.listMembers(trip.id)).single.role.label, '隊長');

    connectivity.isOnline = true;
    await captainRepo.sync();
    expect(database.trips[trip.id]?.title, '京都自由行');
    expect(database.trips[trip.id]?.expectedReturnAt, trip.expectedReturnAt);

    final friend = person('friend', '阿強', birthday: '2010-01-01');
    final friendRepo = OfflineTripRepository(
      local: TripLocalStore(MemoryDocumentStore()),
      remote: MemoryTripRemote(
        database: database,
        currentUserId: () => friend.id,
      ),
      currentAccount: () => friend,
      clock: FixedDeviceClock(DateTime.utc(2026, 10, 26, 2)),
      ids: SequentialId(),
      connectivity: connectivity,
    );
    final joined = await friendRepo.joinWithInviteCode(
      trip.inviteCode.toLowerCase(),
    );
    final members = await friendRepo.listMembers(joined.id);
    expect(
      members.map((member) => member.role.label),
      containsAll(['隊長', '一般成員']),
    );
    expect(
      members.singleWhere((member) => member.userId == 'friend').isMinor,
      isTrue,
    );

    final stranger = person('stranger', '路人');
    final strangerRepo = OfflineTripRepository(
      local: TripLocalStore(MemoryDocumentStore()),
      remote: MemoryTripRemote(
        database: database,
        currentUserId: () => stranger.id,
      ),
      currentAccount: () => stranger,
      clock: FixedDeviceClock(DateTime.utc(2026, 10, 26, 2)),
      ids: SequentialId(),
      connectivity: connectivity,
    );
    await expectLater(
      strangerRepo.getTrip(trip.id),
      throwsA(isA<TripAccessDenied>()),
    );
    expect(await strangerRepo.local.readTrip(trip.id), isNull);
  });

  test('非成員即使遠端沒擋，repository 也不把旅程放進本機', () async {
    final database = MemoryTripDatabase();
    final captain = person('captain', '隊長');
    final connectivity = ConnectivityProbe(isOnline: true);
    final captainRepo = OfflineTripRepository(
      local: TripLocalStore(MemoryDocumentStore()),
      remote: MemoryTripRemote(
        database: database,
        currentUserId: () => captain.id,
      ),
      currentAccount: () => captain,
      clock: FixedDeviceClock(DateTime.utc(2026, 10, 26, 1)),
      ids: SequentialId(),
      connectivity: connectivity,
    );
    final trip = await captainRepo.createTrip(
      const NewTripForm(
        title: '台南',
        startDate: '2026-12-01',
        endDate: '2026-12-02',
        timeZone: 'Asia/Taipei',
        returnDate: '',
        returnTime: '',
      ),
    );
    final stranger = person('stranger', '路人');
    final strangerRepo = OfflineTripRepository(
      local: TripLocalStore(MemoryDocumentStore()),
      remote: MemoryTripRemote(
        database: database,
        currentUserId: () => stranger.id,
        enforceMembership: false,
      ),
      currentAccount: () => stranger,
      clock: FixedDeviceClock(DateTime.utc(2026, 10, 26, 1)),
      ids: SequentialId(),
      connectivity: connectivity,
    );
    await expectLater(
      strangerRepo.getTrip(trip.id),
      throwsA(isA<TripAccessDenied>()),
    );
    expect(await strangerRepo.local.readTrip(trip.id), isNull);
  });

  test('改成比現在早的預計回程時間會被擋下，原本的時間不變', () async {
    final world = TestWorld(now: DateTime.utc(2026, 10, 26, 1));
    await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    );
    final trip = await world.trips.createTrip(sampleForm());
    final original = trip.expectedReturnAt;
    world.clock.elapsed = const Duration(days: 12);
    await expectLater(
      world.trips.updateExpectedReturnTime(
        tripId: trip.id,
        proposed: DateTime.utc(2026, 11, 5, 9),
      ),
      throwsA(isA<ValidationException>()),
    );
    expect((await world.trips.getTrip(trip.id)).expectedReturnAt, original);
  });

  test('一般成員改預計回程時間會變成修改申請，隊長同意後才寫入', () async {
    final database = MemoryTripDatabase()
      ..clock = DateTime.utc(2026, 10, 26, 1);
    final connectivity = ConnectivityProbe(isOnline: true);
    final captain = person('captain', '隊長');
    final captainRepo = OfflineTripRepository(
      local: TripLocalStore(MemoryDocumentStore()),
      remote: MemoryTripRemote(
        database: database,
        currentUserId: () => captain.id,
      ),
      currentAccount: () => captain,
      clock: FixedDeviceClock(DateTime.utc(2026, 10, 26, 1)),
      ids: SequentialId(),
      connectivity: connectivity,
    );
    final trip = await captainRepo.createTrip(
      sampleForm(returnDate: '', returnTime: ''),
    );
    final friend = person('friend', '阿強');
    final friendRepo = OfflineTripRepository(
      local: TripLocalStore(MemoryDocumentStore()),
      remote: MemoryTripRemote(
        database: database,
        currentUserId: () => friend.id,
      ),
      currentAccount: () => friend,
      clock: FixedDeviceClock(DateTime.utc(2026, 10, 26, 1)),
      ids: SequentialId(),
      connectivity: connectivity,
    );
    await friendRepo.joinWithInviteCode(trip.inviteCode);
    final proposed = DateTime.utc(2026, 11, 5, 12);
    final request = await friendRepo.submitExpectedReturnRequest(
      tripId: trip.id,
      proposed: proposed,
    );
    expect(request.expiresAt, isNotNull);
    expect((await captainRepo.getTrip(trip.id)).expectedReturnAt, isNull);
    final updated = await captainRepo.approveRequest(
      tripId: trip.id,
      requestId: request.id,
    );
    expect(updated.expectedReturnAt, proposed);
    await friendRepo.sync();
    expect((await friendRepo.getTrip(trip.id)).expectedReturnAt, proposed);
  });

  // Codex 審核 d5ea1ff 的 P1／P2：核准要一次寫完，失敗時伺服器不能只寫一半，
  // 也不能弄丟核准前就在佇列裡的申請項目。
  for (final queuedRequest in [false, true]) {
    test(
      queuedRequest
          ? '線上核准失敗時，保留核准前已排隊的申請項目，之後仍能上傳'
          : '線上核准失敗時，伺服器旅程與申請都不變，本機還原',
      () async {
        final clock = FixedDeviceClock(DateTime.utc(2026, 10, 26, 1));
        final database = MemoryTripDatabase()..clock = clock.current;
        final remote = _FailingApprovalRemote(
          database: database,
          currentUserId: () => 'host',
        );
        final repo = _repo(clock: clock, database: database, remote: remote);
        final trip = await repo.createTrip(_form());
        final request = _pendingApproval(trip.id, clock.current);
        final requestOp = SyncOp(
          type: SyncOpType.upsertRequest,
          tripId: trip.id,
          entityId: request.id,
        );
        if (queuedRequest) {
          // 申請只在這台手機上，還沒上傳。
          await repo.local.saveRequest(request);
          await repo.local.enqueue(requestOp);
        } else {
          database.requests[trip.id] = {request.id: request};
        }
        remote.failApprovals = true;
        remote.writes.clear();

        await expectLater(
          repo.approveRequest(tripId: trip.id, requestId: request.id),
          throwsA(
            isA<ServerWriteException>().having(
              (error) => error.message,
              'message',
              AppStrings.approveWriteFailed,
            ),
          ),
        );

        // P1：伺服器全部沒寫入。
        expect(remote.writes, ['approve']);
        expect(database.trips[trip.id]!.expectedReturnAt, isNull);
        expect(
          database.requests[trip.id]?[request.id]?.status,
          queuedRequest ? isNull : RequestStatus.pending,
        );
        // 本機回到核准前。
        expect(
          (await repo.local.readTrip(trip.id))!.expectedReturnAt,
          trip.expectedReturnAt,
        );
        final pending = (await repo.local.readRequests(trip.id)).single;
        expect(pending.status, RequestStatus.pending);
        expect(pending.resolvedAt, isNull);
        expect(pending.resolvedBy, isNull);
        // P2：核准前已排隊的申請項目要留著。
        final queue = await repo.local.readQueue();
        expect(queue.any((op) => op.sameAs(requestOp)), queuedRequest);
        expect(queue.where((op) => op.type == SyncOpType.upsertTrip), isEmpty);

        if (queuedRequest) {
          remote.failApprovals = false;
          await repo.sync();
          expect(
            database.requests[trip.id]![request.id]!.status,
            RequestStatus.pending,
            reason: '原本的 pending 申請恢復連線後仍要上傳',
          );
          expect(await repo.local.readQueue(), isEmpty);
        }
      },
    );
  }

  test('線上核准成功時旅程與申請一起寫入，佇列清空', () async {
    final clock = FixedDeviceClock(DateTime.utc(2026, 10, 26, 1));
    final database = MemoryTripDatabase()..clock = clock.current;
    final remote = _FailingApprovalRemote(
      database: database,
      currentUserId: () => 'host',
    );
    final repo = _repo(clock: clock, database: database, remote: remote);
    final trip = await repo.createTrip(_form());
    final request = _pendingApproval(trip.id, clock.current);
    database.requests[trip.id] = {request.id: request};
    remote.writes.clear();

    final approved = await repo.approveRequest(
      tripId: trip.id,
      requestId: request.id,
    );

    expect(approved.expectedReturnAt, request.proposedExpectedReturnAt);
    expect(remote.writes, ['approve']);
    expect(
      database.trips[trip.id]!.expectedReturnAt,
      request.proposedExpectedReturnAt,
    );
    final saved = database.requests[trip.id]![request.id]!;
    expect(saved.status, RequestStatus.approved);
    expect(saved.resolvedBy, 'host');
    expect(await repo.local.readQueue(), isEmpty);
  });

  test('伺服器上已有人拒絕時，核准失敗且伺服器旅程不變', () async {
    final clock = FixedDeviceClock(DateTime.utc(2026, 10, 26, 1));
    final database = MemoryTripDatabase()..clock = clock.current;
    final remote = _FailingApprovalRemote(
      database: database,
      currentUserId: () => 'host',
    );
    final repo = _repo(clock: clock, database: database, remote: remote);
    final trip = await repo.createTrip(_form());
    final request = _pendingApproval(trip.id, clock.current);
    // 這台手機還以為是 pending（佇列裡有它的項目，所以不會先重抓），
    // 伺服器上另一位副隊長已經拒絕了。
    final requestOp = SyncOp(
      type: SyncOpType.upsertRequest,
      tripId: trip.id,
      entityId: request.id,
    );
    await repo.local.saveRequest(request);
    await repo.local.enqueue(requestOp);
    database.requests[trip.id] = {
      request.id: request.copy(
        status: RequestStatus.rejected,
        resolvedAt: clock.current,
        resolvedBy: 'deputy',
      ),
    };
    await expectLater(
      repo.approveRequest(tripId: trip.id, requestId: request.id),
      throwsA(
        isA<RequestHandledException>().having(
          (error) => error.message,
          'message',
          AppStrings.requestHandled,
        ),
      ),
    );
    expect(database.trips[trip.id]!.expectedReturnAt, isNull);
    expect(
      database.requests[trip.id]![request.id]!.status,
      RequestStatus.rejected,
    );
    expect(
      (await repo.local.readTrip(trip.id))!.expectedReturnAt,
      trip.expectedReturnAt,
    );
    // 之後同步不能用 pending 蓋掉伺服器的決定，也不能卡住佇列。
    await repo.sync();
    expect(
      database.requests[trip.id]![request.id]!.status,
      RequestStatus.rejected,
    );
    expect(await repo.local.readQueue(), isEmpty);
    expect(
      (await repo.local.readRequests(trip.id)).single.status,
      RequestStatus.rejected,
    );
  });

  for (final expired in [false, true]) {
    for (final queued in expired ? [false, true] : [true]) {
      final name = expired
          ? '處理過期申請只更新本機並拋出過期錯誤（已有排隊操作：$queued）'
          : '離線核准時只排一筆申請項目，連線後旅程與申請一起寫入';
      test(name, () async {
        final clock = FixedDeviceClock(DateTime.utc(2026, 10, 26, 1));
        final database = MemoryTripDatabase()..clock = clock.current;
        final repo = _repo(
          clock: clock,
          database: database,
          remote: MemoryTripRemote(
            database: database,
            currentUserId: () => 'host',
          ),
        );
        final trip = await repo.createTrip(_form());
        repo.connectivity.isOnline = false;
        final request = ModificationRequest(
          id: 'pending-request',
          tripId: trip.id,
          requesterId: 'friend',
          requesterName: '成員',
          type: ModificationType.expectedReturnTime,
          proposedExpectedReturnAt: DateTime.utc(2026, 12, 3, 8),
          status: RequestStatus.pending,
          createdAt: clock.current.subtract(const Duration(hours: 2)),
          expiresAt: expired
              ? clock.current
              : clock.current.add(const Duration(hours: 1)),
        );
        await repo.local.saveRequest(request);
        if (queued) {
          await repo.local.enqueue(
            SyncOp(
              type: SyncOpType.upsertRequest,
              tripId: trip.id,
              entityId: request.id,
            ),
          );
        }

        final resolving = repo.approveRequest(
          tripId: trip.id,
          requestId: request.id,
        );
        if (expired) {
          await expectLater(
            resolving,
            throwsA(
              isA<ValidationException>().having(
                (error) => error.message,
                'message',
                AppStrings.requestExpired,
              ),
            ),
          );
          expect(await repo.local.readQueue(), isEmpty);
          expect(
            (await repo.local.readTrip(trip.id))!.expectedReturnAt,
            isNull,
          );
        } else {
          final updated = await resolving;
          expect(updated.expectedReturnAt, request.proposedExpectedReturnAt);
          final queue = await repo.local.readQueue();
          // 核准只排一筆申請項目；送出時旅程與申請在同一個 batch 寫入。
          expect(queue.map((op) => op.type), [SyncOpType.upsertRequest]);
          expect(queue.every((op) => op.tripId == trip.id), isTrue);
          expect(queue.last.entityId, request.id);
        }
        expect(
          (await repo.local.readRequests(trip.id)).single.status,
          expired ? RequestStatus.expired : RequestStatus.approved,
        );
        expect(database.trips[trip.id]!.expectedReturnAt, isNull);
        repo.connectivity.isOnline = true;
        await repo.sync();
        expect(await repo.local.readQueue(), isEmpty);
        expect(
          database.trips[trip.id]!.expectedReturnAt,
          expired ? null : request.proposedExpectedReturnAt,
        );
      });
    }
  }

  test('6 人沒有副隊長時申請不過期，指定副隊長後角色會顯示', () async {
    final database = MemoryTripDatabase()
      ..clock = DateTime.utc(2026, 10, 26, 1);
    final connectivity = ConnectivityProbe(isOnline: true);
    final clock = FixedDeviceClock(DateTime.utc(2026, 10, 26, 1));
    final captain = person('captain', '隊長');
    final repos = <String, OfflineTripRepository>{};
    OfflineTripRepository repoFor(UserAccount account) {
      return repos.putIfAbsent(account.id, () {
        return OfflineTripRepository(
          local: TripLocalStore(MemoryDocumentStore()),
          remote: MemoryTripRemote(
            database: database,
            currentUserId: () => account.id,
          ),
          currentAccount: () => account,
          clock: clock,
          ids: SequentialId(),
          connectivity: connectivity,
        );
      });
    }

    final trip = await repoFor(captain).createTrip(
      const NewTripForm(
        title: '八人團',
        startDate: '2026-12-01',
        endDate: '2026-12-03',
        timeZone: 'Asia/Taipei',
        returnDate: '',
        returnTime: '',
      ),
    );
    final others = [for (var i = 0; i < 5; i++) person('m$i', '成員$i')];
    for (final member in others) {
      await repoFor(member).joinWithInviteCode(trip.inviteCode);
    }
    final request = await repoFor(others.first).submitExpectedReturnRequest(
      tripId: trip.id,
      proposed: DateTime.utc(2026, 12, 3, 8),
    );
    expect(request.expiresAt, isNull);
    await repoFor(captain).assignViceCaptain(tripId: trip.id, userId: 'm0');
    final labels = (await repoFor(captain).listMembers(trip.id))
        .map((member) => member.role.label);
    expect(labels, containsAll(['隊長', '副隊長', '一般成員']));
    await expectLater(
      repoFor(captain).assignViceCaptain(tripId: trip.id, userId: 'captain'),
      throwsA(isA<RoleChangeException>()),
    );
  });

  test('離線編輯同一天行程時，校正後較晚的版本勝出，另一版進修改紀錄', () async {
    final database = MemoryTripDatabase()
      ..clock = DateTime.utc(2026, 10, 26, 10);
    final connectivity = ConnectivityProbe(isOnline: true);
    final captain = person('captain', '隊長');
    final friend = person('friend', '阿強');
    final captainClock = FixedDeviceClock(
      DateTime.utc(2026, 10, 26, 10),
      elapsed: const Duration(seconds: 10),
    );
    final friendClock = FixedDeviceClock(
      DateTime.utc(2026, 10, 26, 10),
      elapsed: const Duration(seconds: 10),
    );
    final captainRepo = OfflineTripRepository(
      local: TripLocalStore(MemoryDocumentStore()),
      remote: MemoryTripRemote(
        database: database,
        currentUserId: () => captain.id,
      ),
      currentAccount: () => captain,
      clock: captainClock,
      ids: SequentialId(),
      connectivity: connectivity,
    );
    final friendRepo = OfflineTripRepository(
      local: TripLocalStore(MemoryDocumentStore()),
      remote: MemoryTripRemote(
        database: database,
        currentUserId: () => friend.id,
      ),
      currentAccount: () => friend,
      clock: friendClock,
      ids: SequentialId(),
      connectivity: connectivity,
    );
    final trip = await captainRepo.createTrip(
      const NewTripForm(
        title: '行程',
        startDate: '2026-12-01',
        endDate: '2026-12-02',
        timeZone: 'Asia/Taipei',
        returnDate: '',
        returnTime: '',
      ),
    );
    await friendRepo.joinWithInviteCode(trip.inviteCode);
    await friendRepo.sync();
    connectivity.isOnline = false;
    friendClock.current = DateTime.utc(2026, 10, 26, 18);
    friendClock.elapsed = const Duration(seconds: 20);
    await friendRepo.saveItineraryDay(
      ItineraryDay(
        tripId: trip.id,
        date: '2026-12-01',
        spots: const [ItinerarySpot(name: '早的版本', order: 1, placeId: 'early')],
        updatedAt: DateTime.utc(2000),
        authorId: 'ignored',
      ),
    );
    captainClock.current = DateTime.utc(2026, 10, 26, 8);
    captainClock.elapsed = const Duration(seconds: 40);
    await captainRepo.saveItineraryDay(
      ItineraryDay(
        tripId: trip.id,
        date: '2026-12-01',
        spots: const [ItinerarySpot(name: '晚的版本', order: 1, placeId: 'late')],
        updatedAt: DateTime.utc(2000),
        authorId: 'ignored',
      ),
    );
    connectivity.isOnline = true;
    await friendRepo.sync();
    await captainRepo.sync();
    await friendRepo.sync();
    expect(
      (await friendRepo.readItineraryDay(
        trip.id,
        '2026-12-01',
      ))!.spots.single.name,
      '晚的版本',
    );
    expect(
      (await captainRepo.readItineraryRevisions(
        trip.id,
        '2026-12-01',
      )).map((revision) => revision.spots.single.name),
      contains('早的版本'),
    );
  });

  test('本機檔案重開後還讀得到斷網時建立的旅程', () async {
    final file = File(
      '${Directory.systemTemp.path}/group-trip-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    final store = TripLocalStore(FileDocumentStore(file));
    final connectivity = ConnectivityProbe(isOnline: false);
    final captain = person('captain', '隊長');
    final repo = OfflineTripRepository(
      local: store,
      remote: MemoryTripRemote(
        database: MemoryTripDatabase(),
        currentUserId: () => captain.id,
      ),
      currentAccount: () => captain,
      clock: FixedDeviceClock(DateTime.utc(2026, 10, 26, 1)),
      ids: SequentialId(),
      connectivity: connectivity,
    );
    final trip = await repo.createTrip(
      sampleForm(returnDate: '', returnTime: ''),
    );
    final reopened = OfflineTripRepository(
      local: TripLocalStore(FileDocumentStore(file)),
      remote: MemoryTripRemote(
        database: MemoryTripDatabase(),
        currentUserId: () => captain.id,
      ),
      currentAccount: () => captain,
      clock: FixedDeviceClock(DateTime.utc(2026, 10, 26, 2)),
      ids: SequentialId(),
      connectivity: connectivity,
    );
    expect((await reopened.getTrip(trip.id)).title, '京都自由行');
    if (file.existsSync()) file.deleteSync();
  });

  test('同一個邀請碼在 1 小時內可以給多個人使用', () async {
    final world = TestWorld(now: DateTime.utc(2026, 10, 26, 1));
    await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    );
    final trip = await world.trips.createTrip(
      sampleForm(returnDate: '', returnTime: ''),
    );
    final first = await world
        .repositoryFor(person('first', '甲'))
        .joinWithInviteCode(trip.inviteCode);
    final second = await world
        .repositoryFor(person('second', '乙'))
        .joinWithInviteCode(trip.inviteCode.toLowerCase());
    expect(first.id, second.id);
    expect(
      (await world.trips.listMembers(trip.id)).map((member) => member.userId),
      containsAll([world.auth.current!.id, 'first', 'second']),
    );
    expect(world.database.invites.containsKey(trip.inviteCode), isTrue);
  });

  test('加入是否過期只看伺服器時間：差 1 毫秒可以，滿 1 小時與之後不行', () async {
    final world = TestWorld(now: DateTime.utc(2026, 10, 26, 1));
    await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    );
    final trip = await world.trips.createTrip(
      sampleForm(returnDate: '', returnTime: ''),
    );
    final invite = world.database.invites[trip.inviteCode]!;
    expect(
      invite.expiresAt.difference(invite.createdAt),
      const Duration(hours: 1),
    );

    world.database.clock = invite.expiresAt.subtract(
      const Duration(milliseconds: 1),
    );
    final early = await world
        .repositoryFor(
          person('early', '早'),
          deviceClock: FixedDeviceClock(
            invite.createdAt.subtract(const Duration(days: 1)),
          ),
        )
        .joinWithInviteCode(trip.inviteCode);
    expect(early.memberIds, contains('early'));

    world.database.clock = invite.expiresAt;
    await expectLater(
      world
          .repositoryFor(
            person('exact', '準'),
            deviceClock: FixedDeviceClock(invite.createdAt),
          )
          .joinWithInviteCode(trip.inviteCode),
      throwsA(
        isA<InviteExpiredException>().having(
          (error) => error.message,
          'message',
          AppStrings.inviteExpired,
        ),
      ),
    );

    world.database.clock = invite.expiresAt.add(
      const Duration(milliseconds: 1),
    );
    await expectLater(
      world
          .repositoryFor(
            person('late', '晚'),
            deviceClock: FixedDeviceClock(
              invite.expiresAt.add(const Duration(hours: 5)),
            ),
          )
          .joinWithInviteCode(trip.inviteCode),
      throwsA(isA<InviteExpiredException>()),
    );
  });

  test('公開邀請預設開啟；關閉後只有隊長和副隊長能產生，新碼不會使舊碼失效', () async {
    final world = TestWorld(now: DateTime.utc(2026, 10, 26, 1));
    await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    );
    final trip = await world.trips.createTrip(
      sampleForm(returnDate: '', returnTime: ''),
    );
    expect(trip.publicInvite, isTrue);
    final original = world.database.invites[trip.inviteCode]!;
    final member = person('member', '成員');
    final memberRepo = world.repositoryFor(member);
    await memberRepo.joinWithInviteCode(trip.inviteCode);

    final issued = await memberRepo.issueInviteCode(trip.id);
    expect(issued.code, isNot(original.code));
    expect(issued.createdBy, member.id);
    expect(issued.issuerRole, MemberRole.member);
    expect(original.issuerRole, MemberRole.captain);
    expect(
      world.database.invites[original.code]!.expiresAt,
      original.expiresAt,
    );
    expect(
      (await memberRepo.listInvites(trip.id)).map((invite) => invite.code),
      containsAll([original.code, issued.code]),
    );
    final viaOriginal = await world
        .repositoryFor(person('via-old', '舊碼'))
        .joinWithInviteCode(original.code);
    expect(viaOriginal.memberIds, contains('via-old'));
    final viaNew = await world
        .repositoryFor(person('via-new', '新碼'))
        .joinWithInviteCode(issued.code);
    expect(viaNew.memberIds, contains('via-new'));

    await world.trips.setPublicInvite(tripId: trip.id, enabled: false);
    expect((await world.trips.getTrip(trip.id)).publicInvite, isFalse);
    expect(world.database.invites[issued.code]!.expiresAt, issued.expiresAt);
    expect(
      world.database.invites[original.code]!.expiresAt,
      original.expiresAt,
    );
    await expectLater(
      world
          .repositoryFor(person('still', '仍可'))
          .joinWithInviteCode(issued.code),
      throwsA(
        isA<InviteClosedException>().having(
          (error) => error.message,
          'message',
          AppStrings.inviteClosedByPublicInvite,
        ),
      ),
    );
    final viaCaptain = await world
        .repositoryFor(person('leader-code', '隊長碼'))
        .joinWithInviteCode(original.code);
    expect(viaCaptain.memberIds, contains('leader-code'));
    await expectLater(
      memberRepo.issueInviteCode(trip.id),
      throwsA(
        isA<RoleChangeException>().having(
          (error) => error.message,
          'message',
          AppStrings.cannotIssueInvite,
        ),
      ),
    );

    final stored = world.database.members[trip.id]![member.id]!;
    world.database.members[trip.id]![member.id] = stored.copy(
      role: MemberRole.viceCaptain,
    );
    final asVice = await memberRepo.issueInviteCode(trip.id);
    expect(asVice.issuerRole, MemberRole.viceCaptain);
    expect(asVice.code, isNot(original.code));
    final viaVice = await world
        .repositoryFor(person('via-vice', '副隊長碼'))
        .joinWithInviteCode(asVice.code);
    expect(viaVice.memberIds, contains('via-vice'));
    expect(world.database.invites[issued.code]!.expiresAt, issued.expiresAt);

    await memberRepo.setPublicInvite(tripId: trip.id, enabled: true);
    final reopened = await world.trips.getTrip(trip.id);
    expect(reopened.publicInvite, isTrue);
    expect(reopened.invitesResetAt, isNotNull);
    await expectLater(
      world
          .repositoryFor(person('restored', '恢復'))
          .joinWithInviteCode(issued.code),
      throwsA(isA<InviteClosedException>()),
    );
    expect(world.database.invites[issued.code]!.expiresAt, issued.expiresAt);

    await memberRepo.setPublicInvite(tripId: trip.id, enabled: false);
    await expectLater(
      world
          .repositoryFor(person('closed-again', '再開'))
          .joinWithInviteCode(issued.code),
      throwsA(isA<InviteClosedException>()),
    );
    final captainCode = await world.trips.issueInviteCode(trip.id);
    expect(captainCode.issuerRole, MemberRole.captain);
    final viaNewLeader = await world
        .repositoryFor(person('new-leader', '新隊長碼'))
        .joinWithInviteCode(captainCode.code);
    expect(viaNewLeader.memberIds, contains('new-leader'));
    expect(
      world.database.invites[original.code]!.expiresAt,
      original.expiresAt,
    );
    expect(world.database.invites[issued.code]!.expiresAt, issued.expiresAt);

    world.database.members[trip.id]![member.id] = stored;
    await expectLater(
      memberRepo.setPublicInvite(tripId: trip.id, enabled: true),
      throwsA(isA<RoleChangeException>()),
    );
  });

  test('線上建立時邀請碼寫入失敗，不留下旅程或邀請碼', () async {
    final clock = FixedDeviceClock(DateTime.utc(2026, 10, 26, 1));
    final database = MemoryTripDatabase()..clock = clock.current;
    final remote = _FailingInviteRemote(
      database: database,
      currentUserId: () => 'host',
    )..failInvites = true;
    final repo = _repo(clock: clock, database: database, remote: remote);
    await expectLater(
      repo.createTrip(_form()),
      throwsA(
        isA<ServerWriteException>().having(
          (error) => error.message,
          'message',
          AppStrings.serverWriteFailed,
        ),
      ),
    );
    expect(await repo.local.readAllTrips(), isEmpty);
  });

  test('線上產生邀請碼失敗時不顯示新碼，原碼還在', () async {
    final clock = FixedDeviceClock(DateTime.utc(2026, 10, 26, 1));
    final database = MemoryTripDatabase()..clock = clock.current;
    final remote = _FailingInviteRemote(
      database: database,
      currentUserId: () => 'host',
    );
    final repo = _repo(clock: clock, database: database, remote: remote);
    final trip = await repo.createTrip(_form());
    final before = await repo.listInvites(trip.id);
    remote.failInvites = true;
    await expectLater(
      repo.issueInviteCode(trip.id),
      throwsA(isA<ServerWriteException>()),
    );
    final after = await repo.listInvites(trip.id);
    expect(
      after.map((invite) => invite.code),
      before.map((invite) => invite.code),
    );
  });

  test('佇列裡有一筆一直被拒的舊變更，仍可產生邀請碼', () async {
    final clock = FixedDeviceClock(DateTime.utc(2026, 10, 26, 1));
    final database = MemoryTripDatabase()..clock = clock.current;
    final remote = _FailingInviteRemote(
      database: database,
      currentUserId: () => 'host',
    );
    final repo = _repo(clock: clock, database: database, remote: remote);
    final trip = await repo.createTrip(_form());
    remote.failMembers = true;
    final stale = SyncOp(
      type: SyncOpType.upsertMember,
      tripId: trip.id,
      entityId: 'host',
    );
    await repo.local.enqueue(stale);

    final issued = await repo.issueInviteCode(trip.id);

    expect(database.invites[issued.code], isNotNull);
    expect(
      (await repo.listInvites(trip.id)).map((invite) => invite.code),
      contains(issued.code),
    );
    expect(
      (await repo.local.readQueue()).where(
        (op) => op.type == SyncOpType.upsertMember && op.tripId == trip.id,
      ),
      isNotEmpty,
      reason: '被拒的舊變更留在佇列等之後同步，不會被丟掉',
    );
  });

  test('線上建立時伺服器一直沒回應，逾時後不留下旅程', () async {
    final clock = FixedDeviceClock(DateTime.utc(2026, 10, 26, 1));
    final database = MemoryTripDatabase()..clock = clock.current;
    final remote = _FailingInviteRemote(
      database: database,
      currentUserId: () => 'host',
    )..hangInvites = true;
    final repo = _repo(
      clock: clock,
      database: database,
      remote: remote,
      serverWriteTimeout: const Duration(milliseconds: 50),
    );
    await expectLater(
      repo.createTrip(_form()),
      throwsA(isA<ServerWriteException>()),
    );
    expect(await repo.local.readAllTrips(), isEmpty);
  });

  test('線上產生邀請碼時伺服器一直沒回應，逾時後不顯示新碼', () async {
    final clock = FixedDeviceClock(DateTime.utc(2026, 10, 26, 1));
    final database = MemoryTripDatabase()..clock = clock.current;
    final remote = _FailingInviteRemote(
      database: database,
      currentUserId: () => 'host',
    );
    final repo = _repo(
      clock: clock,
      database: database,
      remote: remote,
      serverWriteTimeout: const Duration(milliseconds: 50),
    );
    final trip = await repo.createTrip(_form());
    final before = await repo.listInvites(trip.id);
    remote.hangInvites = true;
    await expectLater(
      repo.issueInviteCode(trip.id),
      throwsA(isA<ServerWriteException>()),
    );
    expect(
      (await repo.listInvites(trip.id)).map((invite) => invite.code),
      before.map((invite) => invite.code),
    );
  });
}

NewTripForm _form() {
  return const NewTripForm(
    title: '寫入失敗',
    startDate: '2026-12-01',
    endDate: '2026-12-03',
    timeZone: 'Asia/Taipei',
    returnDate: '',
    returnTime: '',
  );
}

OfflineTripRepository _repo({
  required FixedDeviceClock clock,
  required MemoryTripDatabase database,
  required MemoryTripRemote remote,
  Duration serverWriteTimeout = const Duration(seconds: 15),
}) {
  const person = UserAccount(
    id: 'host',
    email: 'host@example.com',
    displayName: '隊長',
    birthday: '2000-01-01',
    consentDecided: true,
    analyticsConsent: false,
    crashlyticsConsent: false,
  );
  return OfflineTripRepository(
    local: TripLocalStore(MemoryDocumentStore()),
    remote: remote,
    currentAccount: () => person,
    clock: clock,
    ids: SequentialIdGenerator(),
    connectivity: ConnectivityProbe(isOnline: true),
    serverWriteTimeout: serverWriteTimeout,
  );
}

ModificationRequest _pendingApproval(String tripId, DateTime now) {
  return ModificationRequest(
    id: 'pending-request',
    tripId: tripId,
    requesterId: 'friend',
    requesterName: '成員',
    type: ModificationType.expectedReturnTime,
    proposedExpectedReturnAt: DateTime.utc(2026, 12, 3, 8),
    status: RequestStatus.pending,
    createdAt: now,
    expiresAt: now.add(const Duration(hours: 1)),
  );
}

class _FailingApprovalRemote extends MemoryTripRemote {
  _FailingApprovalRemote({
    required super.database,
    required super.currentUserId,
  });

  /// 模擬 Firestore 拒絕整個核准 batch：旅程與申請都不會寫入。
  bool failApprovals = false;
  final writes = <String>[];

  @override
  Future<void> upsertTrip(Trip trip) async {
    writes.add('upsertTrip');
    await super.upsertTrip(trip);
  }

  @override
  Future<void> upsertRequest(ModificationRequest request) async {
    writes.add('upsertRequest');
    await super.upsertRequest(request);
  }

  @override
  Future<void> approveRequest(ModificationRequest request) async {
    writes.add('approve');
    if (failApprovals) throw TripAccessDenied();
    await super.approveRequest(request);
  }
}

class _FailingInviteRemote extends MemoryTripRemote {
  _FailingInviteRemote({required super.database, required super.currentUserId});

  bool failInvites = false;
  bool failMembers = false;

  /// 模擬 Firestore 斷線時 `set` 排隊、永遠不回應。
  bool hangInvites = false;

  @override
  Future<void> upsertInvite(InviteRecord invite) async {
    if (hangInvites) return Completer<void>().future;
    if (failInvites) throw TripAccessDenied();
    return super.upsertInvite(invite);
  }

  @override
  Future<void> upsertMember(TripMember member) async {
    if (failMembers) throw TripAccessDenied();
    return super.upsertMember(member);
  }
}

class SequentialId implements IdGenerator {
  int _n = 0;

  @override
  String next({int length = 20}) {
    _n += 1;
    return 'id$_n';
  }

  @override
  String inviteCode({int length = 6}) {
    _n += 1;
    return 'CODE${_n.toString().padLeft(2, '0')}';
  }
}
