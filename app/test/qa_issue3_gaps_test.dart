import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/core/ids/id_generator.dart';
import 'package:group_trip/core/persistence/json_document_store.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/trip/data/firestore_paths.dart';
import 'package:group_trip/features/trip/data/memory_trip_remote.dart';
import 'package:group_trip/features/trip/data/offline_trip_repository.dart';
import 'package:group_trip/features/trip/data/trip_local_store.dart';
import 'package:group_trip/features/trip/domain/trip_codec.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/l10n/app_strings.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'support/harness.dart';

/// 對齊 docs/qa/test-plan.md 的 #3 與最終邀請規則。
/// 這些斷言描述同意後的外部行為，不改產品程式。
void main() {
  setUpAll(tzdata.initializeTimeZones);

  UserAccount person(String id, String name) {
    return UserAccount(
      id: id,
      email: '$id@example.com',
      displayName: name,
      birthday: '2000-01-01',
      consentDecided: true,
      analyticsConsent: false,
      crashlyticsConsent: false,
    );
  }

  const form = NewTripForm(
    title: '京都自由行',
    startDate: '2026-11-01',
    endDate: '2026-11-05',
    timeZone: 'Asia/Taipei',
    returnDate: '',
    returnTime: '',
  );

  test('T3-4 無效邀請碼無法加入，並提示找不到這個邀請碼', () async {
    final world = TestWorld(now: DateTime.utc(2026, 10, 26, 1));
    await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    );
    await world.trips.createTrip(form);
    await expectLater(
      world.repositoryFor(person('guest', '路人')).joinWithInviteCode('NOTEXIST'),
      throwsA(
        isA<InviteNotFoundException>().having(
          (error) => error.message,
          'message',
          AppStrings.inviteNotFound,
        ),
      ),
    );
  });

  test('T3-21 本機留著已過期邀請碼，恢復連線後仍被伺服器時間拒絕', () async {
    final world = TestWorld(now: DateTime.utc(2026, 10, 26, 1));
    await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    );
    final trip = await world.trips.createTrip(form);
    final invite = world.database.invites[trip.inviteCode]!;
    final local = TripLocalStore(MemoryDocumentStore());
    await local.saveInvite(invite);
    world.connectivity.isOnline = false;
    world.database.clock = invite.expiresAt.add(const Duration(minutes: 5));
    final guest = world.repositoryFor(
      person('guest', '路人'),
      local: local,
      deviceClock: FixedDeviceClock(invite.createdAt),
    );
    await expectLater(
      guest.joinWithInviteCode(invite.code),
      throwsA(isA<ValidationException>()),
    );
    world.connectivity.isOnline = true;
    await expectLater(
      guest.joinWithInviteCode(invite.code),
      throwsA(
        isA<InviteExpiredException>().having(
          (error) => error.message,
          'message',
          AppStrings.inviteExpired,
        ),
      ),
    );
    expect(await local.readTrip(trip.id), isNull);
  });

  test('T3-10 副隊長可以切換公開邀請', () async {
    final world = TestWorld(now: DateTime.utc(2026, 10, 26, 1));
    await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    );
    final trip = await world.trips.createTrip(form);
    final deputy = person('deputy', '阿強');
    final deputyRepo = world.repositoryFor(deputy);
    await deputyRepo.joinWithInviteCode(trip.inviteCode);
    final stored = world.database.members[trip.id]![deputy.id]!;
    world.database.members[trip.id]![deputy.id] = stored.copy(
      role: MemberRole.viceCaptain,
    );
    final updated = await deputyRepo.setPublicInvite(
      tripId: trip.id,
      enabled: false,
    );
    expect(updated.publicInvite, isFalse);
    final reopened = await deputyRepo.setPublicInvite(
      tripId: trip.id,
      enabled: true,
    );
    expect(reopened.publicInvite, isTrue);
  });

  test('T3-16 關掉公開邀請後，一般成員未過期的碼立刻不能加入，隊長的碼可以', () async {
    final world = TestWorld(now: DateTime.utc(2026, 10, 26, 1));
    await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    );
    final trip = await world.trips.createTrip(form);
    final member = person('member', '小華');
    final memberRepo = world.repositoryFor(member);
    await memberRepo.joinWithInviteCode(trip.inviteCode);
    final memberCode = await memberRepo.issueInviteCode(trip.id);
    await world.trips.setPublicInvite(tripId: trip.id, enabled: false);

    await expectLater(
      world.repositoryFor(person('blocked', '被拒')).joinWithInviteCode(memberCode.code),
      throwsA(isA<TripException>()),
    );
    final viaCaptain = await world
        .repositoryFor(person('ok', '可加入'))
        .joinWithInviteCode(trip.inviteCode);
    expect(viaCaptain.memberIds, contains('ok'));
    expect(viaCaptain.memberIds, isNot(contains('blocked')));
  });

  test('T3-22 離線期間公開邀請被關掉，恢復連線後一般成員的碼不能加入', () async {
    final world = TestWorld(now: DateTime.utc(2026, 10, 26, 1));
    await world.auth.signUp(
      email: 'ada@example.com',
      password: 'password1',
      displayName: '小美',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    );
    final trip = await world.trips.createTrip(form);
    final member = person('member', '小華');
    final memberRepo = world.repositoryFor(member);
    await memberRepo.joinWithInviteCode(trip.inviteCode);
    final memberCode = await memberRepo.issueInviteCode(trip.id);

    final guestLocal = TripLocalStore(MemoryDocumentStore());
    await guestLocal.saveInvite(memberCode);
    final guestConn = ConnectivityProbe(isOnline: false);
    final guest = OfflineTripRepository(
      local: guestLocal,
      remote: MemoryTripRemote(
        database: world.database,
        currentUserId: () => 'guest',
      ),
      currentAccount: () => person('guest', '路人'),
      clock: FixedDeviceClock(world.clock.current),
      ids: SequentialIdGenerator(),
      connectivity: guestConn,
    );
    await world.trips.setPublicInvite(tripId: trip.id, enabled: false);
    await expectLater(
      guest.joinWithInviteCode(memberCode.code),
      throwsA(isA<ValidationException>()),
    );
    guestConn.isOnline = true;
    await expectLater(
      guest.joinWithInviteCode(memberCode.code),
      throwsA(isA<TripException>()),
    );
    expect(await guestLocal.readTrip(trip.id), isNull);
  });

  test('用戶端旅程文件欄位對齊規則：leaderId、invitesOpen，沒有 captainId', () {
    final now = DateTime.utc(2026, 10, 26, 1);
    final map = TripCodec.tripToMap(
      Trip(
        id: 'trip-1',
        title: '京都自由行',
        captainId: 'leader-1',
        startDate: '2026-11-01',
        endDate: '2026-11-05',
        timeZone: 'Asia/Taipei',
        expectedReturnAt: null,
        inviteCode: 'ABCD2345',
        status: TripStatus.planning,
        memberIds: const ['leader-1'],
        createdAt: now,
        updatedAt: now,
      ),
    );
    expect(map['schemaVersion'], 1);
    expect(map['leaderId'], 'leader-1');
    expect(map['invitesOpen'], isTrue);
    expect(map['invitesResetAt'], isNull);
    expect(map.containsKey('captainId'), isFalse);
    expect(map.containsKey('publicInvite'), isFalse);
    expect(map.containsKey('memberIds'), isFalse);
    expect(map.containsKey('inviteCode'), isFalse);
  });

  test('用戶端角色字串與邀請集合對齊 leader、deputy、invites', () {
    expect(MemberRole.captain.wire, 'leader');
    expect(MemberRole.viceCaptain.wire, 'deputy');
    expect(MemberRole.member.wire, 'member');
    expect(FirestorePaths.inviteCodes, 'invites');
    final invite = TripCodec.inviteToMap(
      InviteRecord(
        code: 'ABCD2345',
        tripId: 'trip-1',
        createdBy: 'leader-1',
        createdAt: DateTime.utc(2026, 10, 26, 1),
        expiresAt: DateTime.utc(2026, 10, 26, 2),
      ),
    );
    expect(invite['creatorRole'], 'leader');
    expect(invite['tripTitle'], isA<String>());
    expect(invite['active'], isTrue);
    expect(invite.containsKey('code'), isFalse);
  });

  test('正式環境產生的邀請碼長度是 8 到 12', () {
    final code = RandomIdGenerator(Random(1)).inviteCode();
    expect(code.length, inInclusiveRange(8, 12));
    expect(RegExp(r'^[A-Za-z0-9]+$').hasMatch(code), isTrue);
  });

  test('註冊寫入 users 的欄位是 birthdate，且不含分析同意', () {
    const account = UserAccount(
      id: 'u1',
      email: 'ada@example.com',
      displayName: '小美',
      birthday: '2000-01-01',
      consentDecided: false,
      analyticsConsent: false,
      crashlyticsConsent: false,
    );
    final map = account.toPublicMap();
    expect(map.containsKey('birthdate'), isTrue);
    expect(map.containsKey('birthday'), isFalse);
    expect(map.containsKey('analyticsConsent'), isFalse);
    expect(map.containsKey('crashlyticsConsent'), isFalse);
    expect(map.containsKey('consentDecided'), isFalse);
  });
}
