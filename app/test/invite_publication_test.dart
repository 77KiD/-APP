import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/core/ids/id_generator.dart';
import 'package:group_trip/core/persistence/json_document_store.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/trip/data/memory_trip_remote.dart';
import 'package:group_trip/features/trip/data/offline_trip_repository.dart';
import 'package:group_trip/features/trip/data/trip_local_store.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_codec.dart';
import 'package:group_trip/features/trip/presentation/trip_detail_page.dart';
import 'package:group_trip/l10n/app_strings.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'support/harness.dart';

NewTripForm form() => const NewTripForm(
  title: '雙機邀請測試',
  startDate: '2026-11-01',
  endDate: '2026-11-05',
  timeZone: 'Asia/Taipei',
  returnDate: '',
  returnTime: '',
);

class RecoverableConnectivity extends ConnectivityProbe {
  RecoverableConnectivity() : super(isOnline: false);
  bool physicalOnline = false;
  int refreshCount = 0;
  @override
  Future<void> refresh() async {
    refreshCount++;
    isOnline = physicalOnline;
  }
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  for (final state in [
    'disabled',
    'missing',
    'wrong-trip',
    'error',
    'timeout',
    'offline',
  ]) {
    test('分享重驗已確認的碼：$state', () async {
      late _KnownInviteRemote remote;
      final world = TestWorld(
        remoteFactory: (database, user) {
          remote = _KnownInviteRemote(database: database, currentUserId: user);
          return remote;
        },
      );
      await world.auth.signUp(
        email: 'host@example.com',
        password: 'password1',
        displayName: '隊長',
        birthday: '2000-01-01',
        birthdayConsent: true,
        today: world.clock.current,
      );
      final trip = await world.trips.createTrip(form());
      final original = (await world.trips.local.readInvite(trip.inviteCode))!;
      expect(original.serverConfirmed, isTrue);
      remote.reads.clear();
      await world.trips.listMyTrips();
      await world.trips.getTrip(trip.id);
      await world.trips.listInvites(trip.id);
      expect(remote.reads, isEmpty, reason: '一般載入不逐碼重驗已確認的碼');
      remote.state = state;
      if (state == 'offline') world.connectivity.isOnline = false;
      final repository = OfflineTripRepository(
        local: world.trips.local,
        remote: remote,
        currentAccount: () => world.auth.current,
        clock: world.clock,
        ids: RandomIdGenerator(),
        connectivity: world.connectivity,
        serverWriteTimeout: const Duration(milliseconds: 5),
      );
      final result = await repository.revalidateInvites(trip.id);
      expect(result.failed, ['error', 'timeout', 'offline'].contains(state));
      if (state == 'disabled') {
        expect(result.invites.single.active, isFalse);
        expect(
          (await repository.local.readInvite(original.code))!.active,
          isFalse,
        );
      } else {
        expect(result.invites, isEmpty);
      }
      if (state == 'missing' || state == 'wrong-trip') {
        expect(
          (await repository.local.readInvite(original.code))!.active,
          isFalse,
          reason: '下次一般載入不該再出現分享入口',
        );
      }
      if (state == 'error' || state == 'timeout' || state == 'offline') {
        expect(
          (await repository.local.readInvite(original.code))!.active,
          isTrue,
          reason: '暫時無法確認不等於碼已失效',
        );
      }
      expect(remote.reads, state == 'offline' ? isEmpty : [original.code]);
    });
  }

  group('分享重驗以伺服器的旅程為準', () {
    late _KnownInviteRemote remote;
    late TestWorld world;
    late Trip trip;

    setUp(() async {
      world = TestWorld(
        remoteFactory: (database, user) {
          remote = _KnownInviteRemote(database: database, currentUserId: user);
          return remote;
        },
      );
      await world.auth.signUp(
        email: 'host@example.com',
        password: 'password1',
        displayName: '隊長',
        birthday: '2000-01-01',
        birthdayConsent: true,
        today: world.clock.current,
      );
      trip = await world.trips.createTrip(form());
    });

    test('伺服器的旅程已結束，本機仍是舊狀態時不回傳任何碼', () async {
      world.database.trips[trip.id] = trip.copy(status: TripStatus.ended);
      expect((await world.trips.local.readTrip(trip.id))!.status, trip.status);

      final result = await world.trips.revalidateInvites(trip.id);

      expect(result.invites, isEmpty);
      expect(result.failed, isFalse);
    });

    test('伺服器已關閉公開邀請時，一般成員較早的碼不回傳', () async {
      final createdAt = world.clock.current;
      final memberInvite = InviteRecord(
        code: 'MEMBER01',
        tripId: trip.id,
        createdBy: 'member-1',
        issuerRole: MemberRole.member,
        serverConfirmed: true,
        createdAt: createdAt,
        expiresAt: createdAt.add(TripPolicy.inviteLifetime),
      );
      world.database.invites[memberInvite.code] = memberInvite;
      await world.trips.local.saveInvite(memberInvite);
      world.database.trips[trip.id] = trip.copy(
        setInvitesResetAt: true,
        invitesResetAt: createdAt.add(const Duration(minutes: 1)),
      );

      final result = await world.trips.revalidateInvites(trip.id);

      expect(result.invites.map((invite) => invite.code), [trip.inviteCode]);
      expect(result.failed, isFalse);
    });

    for (final state in ['error', 'missing', 'timeout']) {
      test('確認不了伺服器的旅程（$state）不回傳任何碼', () async {
        remote.tripState = state;
        final repository = OfflineTripRepository(
          local: world.trips.local,
          remote: remote,
          currentAccount: () => world.auth.current,
          clock: world.clock,
          ids: RandomIdGenerator(),
          connectivity: world.connectivity,
          serverWriteTimeout: const Duration(milliseconds: 5),
        );

        final result = await repository.revalidateInvites(trip.id);

        expect(result.invites, isEmpty);
        expect(result.failed, isTrue);
        expect(
          (await repository.local.readInvite(trip.inviteCode))!.active,
          isTrue,
        );
      });
    }

    test('尚未發布的本機碼查不到時保留待同步狀態', () async {
      final createdAt = world.clock.current;
      final pending = InviteRecord(
        code: 'PENDING1',
        tripId: trip.id,
        createdBy: 'member-1',
        createdAt: createdAt,
        expiresAt: createdAt.add(TripPolicy.inviteLifetime),
      );
      await world.trips.local.saveInvite(pending);

      final result = await world.trips.revalidateInvites(trip.id);

      expect(result.invites.map((invite) => invite.code), [trip.inviteCode]);
      final kept = (await world.trips.local.readInvite(pending.code))!;
      expect(kept.active, isTrue);
      expect(kept.serverConfirmed, isFalse);
    });

    test('離線產生、尚未發布的碼經過重驗後，仍會在同步時發布', () async {
      world.connectivity.isOnline = false;
      final queued = await world.trips.issueInviteCode(trip.id);
      expect(queued.serverConfirmed, isFalse);
      expect(world.database.invites[queued.code], isNull);
      world.connectivity.isOnline = true;

      final result = await world.trips.revalidateInvites(trip.id);
      expect(
        result.invites.map((invite) => invite.code),
        isNot(contains(queued.code)),
      );

      await world.trips.sync();

      expect(world.database.invites[queued.code]?.active, isTrue);
      final published = (await world.trips.local.readInvite(queued.code))!;
      expect(published.active, isTrue);
      expect(published.serverConfirmed, isTrue);
    });
  });

  testWidgets('旅程頁對已失效的碼顯示失效，不能複製，也能產生新碼', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final world = TestWorld();
    await world.auth.signUp(
      email: 'captain@example.com',
      password: 'password1',
      displayName: '隊長',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    );
    final trip = await world.trips.createTrip(form());
    world.database.invites.remove(trip.inviteCode);
    await world.trips.revalidateInvites(trip.id);

    await tester.pumpWidget(
      wrapPage(world.deps, TripDetailPage(tripId: trip.id)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings.inviteInactive(trip.inviteCode)),
      findsOneWidget,
    );
    expect(find.text(AppStrings.copyInviteCode(trip.inviteCode)), findsNothing);
    final issue = tester.widget<OutlinedButton>(
      find.byKey(const Key('issue-invite')),
    );
    expect(issue.onPressed, isNotNull);
  });

  test('recovered network publishes a usable code before reporting success', () async {
    final clock = FixedDeviceClock(DateTime.utc(2026, 10, 26, 1));
    final database = MemoryTripDatabase()..clock = clock.current;
    final connectivity = RecoverableConnectivity();
    const captain = UserAccount(
      id: 'captain',
      email: 'captain@example.com',
      displayName: '隊長',
      birthday: '2000-01-01',
      consentDecided: true,
      analyticsConsent: false,
      crashlyticsConsent: false,
    );
    final repository = OfflineTripRepository(
      local: TripLocalStore(MemoryDocumentStore()),
      remote: MemoryTripRemote(
        database: database,
        currentUserId: () => captain.id,
      ),
      currentAccount: () => captain,
      clock: clock,
      ids: RandomIdGenerator(),
      connectivity: connectivity,
    );
    final trip = await repository.createTrip(form());
    expect(database.invites, isEmpty);
    // Wi-Fi recovered while the user stayed on the detail page; no Home reload.
    connectivity.physicalOnline = true;
    final invite = await repository.issueInviteCode(trip.id);
    expect(
      database.invites.containsKey(invite.code),
      isTrue,
      reason: 'A successful issue result must refer to a code another phone can read',
    );
    expect(invite.serverConfirmed, isTrue);
    const joiner = UserAccount(
      id: 'joiner',
      email: 'joiner@example.com',
      displayName: '成員',
      birthday: '2000-01-01',
      consentDecided: true,
      analyticsConsent: false,
      crashlyticsConsent: false,
    );
    final joinRepository = OfflineTripRepository(
      local: TripLocalStore(MemoryDocumentStore()),
      remote: MemoryTripRemote(
        database: database,
        currentUserId: () => joiner.id,
      ),
      currentAccount: () => joiner,
      clock: clock,
      ids: RandomIdGenerator(),
      connectivity: ConnectivityProbe(isOnline: true),
    );
    final fullWidth = String.fromCharCodes(
      invite.code.toLowerCase().runes.map((rune) => rune + 0xfee0),
    );
    expect(
      (await joinRepository.joinWithInviteCode('　$fullWidth　')).id,
      trip.id,
    );
  });

  test(
    'legacy records default to unconfirmed and confirmation stays local',
    () async {
      final invite = InviteRecord(
        code: 'ABCD2345',
        tripId: 'trip',
        createdBy: 'host',
        createdAt: DateTime.utc(2026),
        expiresAt: DateTime.utc(2026, 1, 1, 1),
      );
      final wireMap = TripCodec.inviteToMap(
        invite.withServerConfirmation(true),
      );
      expect(
        TripCodec.inviteFromMap(wireMap, code: invite.code).serverConfirmed,
        isFalse,
      );
      final store = TripLocalStore(MemoryDocumentStore());
      await store.saveInvite(invite.withServerConfirmation(true));
      expect((await store.readInvite(invite.code))!.serverConfirmed, isTrue);
    },
  );

  test('retrying a published code never renews its lifetime', () async {
    final world = TestWorld();
    await world.auth.signUp(
      email: 'captain@example.com',
      password: 'password1',
      displayName: '隊長',
      birthday: '2000-01-01',
      birthdayConsent: true,
      today: world.clock.current,
    );
    final trip = await world.trips.createTrip(form());
    final original = world.database.invites[trip.inviteCode]!;
    await world.trips.local.saveInvite(original); // Simulate lost confirmation.
    await world.trips.local.enqueue(
      SyncOp(
        type: SyncOpType.upsertInvite,
        tripId: trip.id,
        entityId: original.code,
      ),
    );
    world.clock.current = world.clock.current.add(const Duration(minutes: 10));
    world.database.clock = world.clock.current;
    await world.trips.sync();
    expect(
      world.database.invites[original.code]!.expiresAt,
      original.expiresAt,
    );
    expect(
      world.database.invites[original.code]!.createdAt,
      original.createdAt,
    );
    expect(
      (await world.trips.local.readInvite(original.code))!.serverConfirmed,
      isTrue,
    );
  });

  test(
    'unpublished delayed codes acquire their first window on publication',
    () async {
      final world = TestWorld(online: false);
      await world.auth.signUp(
        email: 'captain@example.com',
        password: 'password1',
        displayName: '隊長',
        birthday: '2000-01-01',
        birthdayConsent: true,
        today: world.clock.current,
      );
      final trip = await world.trips.createTrip(form());
      world.clock.current = world.clock.current.add(
        const Duration(minutes: 10),
      );
      world.database.clock = world.clock.current;
      world.connectivity.isOnline = true;
      await world.trips.sync();
      final published = world.database.invites[trip.inviteCode]!;
      expect(
        published.expiresAt,
        world.clock.current.add(const Duration(hours: 1)),
      );
      expect(
        (await world.trips.local.readInvite(published.code))!.serverConfirmed,
        isTrue,
      );
    },
  );

  testWidgets(
    'offline invitation stays unshareable until explicit sync confirms it',
    (tester) async {
      final world = TestWorld(online: false);
      await world.auth.signUp(
        email: 'captain@example.com',
        password: 'password1',
        displayName: '隊長',
        birthday: '2000-01-01',
        birthdayConsent: true,
        today: world.clock.current,
      );
      final trip = await world.trips.createTrip(form());
      expect(world.database.invites, isEmpty);
      await tester.pumpWidget(
        wrapPage(world.deps, TripDetailPage(tripId: trip.id)),
      );
      await tester.pumpAndSettle();
      final copyLabel = find.text(AppStrings.copyInviteCode(trip.inviteCode));
      if (copyLabel.evaluate().isNotEmpty) {
        final button = tester.widget<OutlinedButton>(
          find.ancestor(of: copyLabel, matching: find.byType(OutlinedButton)),
        );
        expect(
          button.onPressed,
          isNull,
          reason: 'There is no server invite; sharing this code guarantees not-found',
        );
      } else {
        expect(find.textContaining('尚未同步'), findsWidgets);
      }
      world.connectivity.isOnline = true;
      await tester.tap(find.byKey(const Key('refresh-invites')));
      await tester.pumpAndSettle();
      expect(world.database.invites.containsKey(trip.inviteCode), isTrue);
      expect(find.byKey(const Key('invite-code')), findsOneWidget);
      expect(
        find.text(AppStrings.copyInviteCode(trip.inviteCode)),
        findsOneWidget,
      );
    },
  );
}

class _KnownInviteRemote extends MemoryTripRemote {
  _KnownInviteRemote({required super.database, required super.currentUserId});
  final reads = <String>[];
  String? state;
  String? tripState;
  @override
  Future<Trip?> fetchTripFromServer(String id) async {
    if (tripState == 'error') throw TripException('讀取失敗');
    if (tripState == 'timeout') return Completer<Trip?>().future;
    if (tripState == 'missing') return null;
    return super.fetchTripFromServer(id);
  }

  @override
  Future<List<InviteRecord>> fetchInvites(String tripId) async => [];
  @override
  Future<InviteRecord?> fetchInvite(String code) async {
    reads.add(code);
    if (state == 'error') throw TripException('讀取失敗');
    if (state == 'timeout') return Completer<InviteRecord?>().future;
    if (state == 'missing') return null;
    final original = await super.fetchInvite(code);
    if (original == null || state == null) return original;
    return InviteRecord(
      code: code,
      tripId: state == 'wrong-trip' ? 'other-trip' : original.tripId,
      createdBy: original.createdBy,
      active: state != 'disabled',
      createdAt: original.createdAt,
      expiresAt: original.expiresAt,
    );
  }
}
