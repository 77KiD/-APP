import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/core/ids/id_generator.dart';
import 'package:group_trip/core/persistence/json_document_store.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/trip/data/memory_trip_remote.dart';
import 'package:group_trip/features/trip/data/offline_trip_repository.dart';
import 'package:group_trip/features/trip/data/trip_local_store.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('時鐘樣本等離線佇列送完才更新，而且不寫 syncAnchors', () async {
    final start = DateTime.utc(2026, 10, 26, 1);
    final clock = FixedDeviceClock(start);
    final database = MemoryTripDatabase()..clock = start;
    final local = TripLocalStore(MemoryDocumentStore());
    final captain = UserAccount(
      id: 'captain',
      email: 'captain@example.com',
      displayName: '隊長',
      birthday: '2000-01-01',
      consentDecided: true,
      analyticsConsent: false,
      crashlyticsConsent: false,
    );
    final remote = _ProbeRemote(
      database: database,
      currentUserId: () => captain.id,
      clock: clock,
    );
    final connectivity = ConnectivityProbe(isOnline: false);
    final repo = OfflineTripRepository(
      local: local,
      remote: remote,
      currentAccount: () => captain,
      clock: clock,
      ids: SequentialIdGenerator(),
      connectivity: connectivity,
    );

    final trip = await repo.createTrip(
      const NewTripForm(
        title: '京都',
        startDate: '2026-12-01',
        endDate: '2026-12-02',
        timeZone: 'Asia/Taipei',
        returnDate: '',
        returnTime: '',
      ),
    );
    expect(await local.readTimeSample(), isNull);
    expect(remote.clockReads, 0);
    expect(database.trips, isEmpty);

    connectivity.isOnline = true;
    await repo.sync();

    final sample = await local.readTimeSample();
    final shifted = start.add(const Duration(hours: 5));
    expect(remote.flushed, isTrue);
    expect(remote.clockReads, 1);
    expect(sample!.deviceNow, shifted);
    expect(sample.serverNow, shifted);
    expect(database.trips[trip.id]!.updatedAt.isBefore(sample.deviceNow), isTrue);

    final forbidden = RegExp(
      r'collection\(\s*(FirestoreSchema|FirestorePaths)\.syncAnchors',
    );
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (forbidden.hasMatch(entity.readAsStringSync())) hits.add(entity.path);
    }
    expect(hits, isEmpty);
  });
}

class _ProbeRemote extends MemoryTripRemote {
  _ProbeRemote({
    required super.database,
    required super.currentUserId,
    required this.clock,
  });

  final FixedDeviceClock clock;
  var flushed = false;
  var clockReads = 0;

  @override
  Future<void> flushPendingWrites() async {
    flushed = true;
    final shifted = clock.current.add(const Duration(hours: 5));
    clock.current = shifted;
    database.clock = shifted;
  }

  @override
  Future<ServerClockReading> readServerClock(
    Future<DateTime> Function() deviceNow,
  ) async {
    clockReads += 1;
    if (!flushed) {
      throw StateError('時鐘樣本在離線佇列送完之前就更新了');
    }
    return super.readServerClock(deviceNow);
  }
}
