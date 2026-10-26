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
    final database = MemoryTripDatabase()..clock = DateTime.utc(2026, 10, 26, 1);
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
    expect((await captainRepo.listMembers(trip.id)).single.role, MemberRole.captain);
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
    final joined = await friendRepo.joinWithInviteCode(trip.inviteCode.toLowerCase());
    final members = await friendRepo.listMembers(joined.id);
    expect(
      members.map((member) => member.role.label),
      containsAll(['隊長', '一般成員']),
    );
    expect(members.singleWhere((member) => member.userId == 'friend').isMinor, isTrue);

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
      remote: MemoryTripRemote(database: database, currentUserId: () => captain.id),
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
    final database = MemoryTripDatabase()..clock = DateTime.utc(2026, 10, 26, 1);
    final connectivity = ConnectivityProbe(isOnline: true);
    final captain = person('captain', '隊長');
    final captainRepo = OfflineTripRepository(
      local: TripLocalStore(MemoryDocumentStore()),
      remote: MemoryTripRemote(database: database, currentUserId: () => captain.id),
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
      remote: MemoryTripRemote(database: database, currentUserId: () => friend.id),
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

  test('6 人沒有副隊長時申請不過期，指定副隊長後角色會顯示', () async {
    final database = MemoryTripDatabase()..clock = DateTime.utc(2026, 10, 26, 1);
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
    final others = [
      for (var i = 0; i < 5; i++) person('m$i', '成員$i'),
    ];
    for (final member in others) {
      await repoFor(member).joinWithInviteCode(trip.inviteCode);
    }
    final request = await repoFor(others.first).submitExpectedReturnRequest(
      tripId: trip.id,
      proposed: DateTime.utc(2026, 12, 3, 8),
    );
    expect(request.expiresAt, isNull);
    await repoFor(captain).assignViceCaptain(tripId: trip.id, userId: 'm0');
    final labels = (await repoFor(captain).listMembers(trip.id)).map(
      (member) => member.role.label,
    );
    expect(labels, containsAll(['隊長', '副隊長', '一般成員']));
    await expectLater(
      repoFor(captain).assignViceCaptain(tripId: trip.id, userId: 'captain'),
      throwsA(isA<RoleChangeException>()),
    );
  });

  test('離線編輯同一天行程時，校正後較晚的版本勝出，另一版進修改紀錄', () async {
    final database = MemoryTripDatabase()..clock = DateTime.utc(2026, 10, 26, 10);
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
      remote: MemoryTripRemote(database: database, currentUserId: () => captain.id),
      currentAccount: () => captain,
      clock: captainClock,
      ids: SequentialId(),
      connectivity: connectivity,
    );
    final friendRepo = OfflineTripRepository(
      local: TripLocalStore(MemoryDocumentStore()),
      remote: MemoryTripRemote(database: database, currentUserId: () => friend.id),
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
      (await friendRepo.readItineraryDay(trip.id, '2026-12-01'))!.spots.single.name,
      '晚的版本',
    );
    expect(
      (await captainRepo.readItineraryRevisions(trip.id, '2026-12-01'))
          .map((revision) => revision.spots.single.name),
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
    expect(invite.expiresAt.difference(invite.createdAt), const Duration(hours: 1));

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

    world.database.clock = invite.expiresAt.add(const Duration(milliseconds: 1));
    await expectLater(
      world
          .repositoryFor(
            person('late', '晚'),
            deviceClock: FixedDeviceClock(invite.expiresAt.add(const Duration(hours: 5))),
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
    final still = await world
        .repositoryFor(person('still', '仍可'))
        .joinWithInviteCode(issued.code);
    expect(still.memberIds, contains('still'));
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
    expect(asVice.code, isNot(original.code));
    expect(
      world.database.invites[original.code]!.expiresAt,
      original.expiresAt,
    );

    world.database.members[trip.id]![member.id] = stored;
    final captainCode = await world.trips.issueInviteCode(trip.id);
    expect(world.database.invites.containsKey(captainCode.code), isTrue);
    expect(
      world.database.invites[original.code]!.expiresAt,
      original.expiresAt,
    );

    await expectLater(
      memberRepo.setPublicInvite(tripId: trip.id, enabled: true),
      throwsA(isA<RoleChangeException>()),
    );
    await world.trips.setPublicInvite(tripId: trip.id, enabled: true);
    final again = await memberRepo.issueInviteCode(trip.id);
    expect(again.code, isNot(original.code));
    expect(world.database.invites.containsKey(original.code), isTrue);
  });
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
