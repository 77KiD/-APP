import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/core/ids/id_generator.dart';
import 'package:group_trip/core/persistence/json_document_store.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/data/firestore_schema.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/trip/data/memory_trip_remote.dart';
import 'package:group_trip/features/trip/data/offline_trip_repository.dart';
import 'package:group_trip/features/trip/data/trip_local_store.dart';
import 'package:group_trip/features/trip/domain/itinerary_day_write.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  final earlier = DateTime.utc(2026, 10, 26, 8);
  final later = DateTime.utc(2026, 10, 26, 12);
  const backups = [
    ItinerarySpot(name: '金閣寺', order: 0, placeId: 'kinkaku'),
  ];

  ItineraryDay day({
    required List<ItinerarySpot> spots,
    required DateTime savedAt,
    required String authorId,
    List<ItinerarySpot>? backupStops,
    bool replaceBackupStops = false,
  }) {
    return ItineraryDay(
      tripId: 'trip',
      date: '2026-12-01',
      spots: spots,
      backupStops: backupStops,
      replaceBackupStops: replaceBackupStops,
      updatedAt: savedAt,
      authorId: authorId,
    );
  }

  test('修改行程只更新有變動的欄位，不會把 backupStops 寫成空清單', () {
    final existing = day(
      spots: const [ItinerarySpot(name: '清水寺', order: 0, placeId: 'kiyomizu')],
      backupStops: backups,
      savedAt: earlier,
      authorId: 'route',
    );
    final edit = day(
      spots: const [ItinerarySpot(name: '伏見稻荷', order: 0, placeId: 'fushimi')],
      backupStops: const [],
      savedAt: later,
      authorId: 'captain',
    );
    final patch = ItineraryDayWrite.changedFields(existing: existing, incoming: edit);
    expect(patch.containsKey(FirestoreSchema.backupStops), isFalse);
    expect(patch.containsKey(FirestoreSchema.serverRestored), isFalse);
    expect(patch.containsKey(LocalOnlyFields.replaceBackupStops), isFalse);
    expect(patch[FirestoreSchema.stops], isNot(existing.spots));
    expect(
      patch.keys,
      isNot(contains(FirestoreSchema.date)),
    );
    expect(patch.keys, containsAll([
      FirestoreSchema.stops,
      FirestoreSchema.clientSavedAt,
      FirestoreSchema.updatedBy,
      FirestoreSchema.updatedAt,
    ]));

    final merged = ItineraryDayWrite.merge(existing: existing, incoming: edit);
    expect(merged.spots.single.name, '伏見稻荷');
    expect(merged.backupStops!.single.name, '金閣寺');

    final copied = existing.copy(
      spots: const [ItinerarySpot(name: '伏見稻荷', order: 0, placeId: 'fushimi')],
      updatedAt: later,
      authorId: 'captain',
    );
    expect(copied.replaceBackupStops, isFalse);
    final copiedPatch = ItineraryDayWrite.changedFields(
      existing: existing,
      incoming: copied,
    );
    expect(copiedPatch.containsKey(FirestoreSchema.backupStops), isFalse);

    final created = ItineraryDayWrite.changedFields(existing: null, incoming: edit);
    expect(created[FirestoreSchema.backupStops], isEmpty);
    expect(created.keys, {
      FirestoreSchema.date,
      FirestoreSchema.stops,
      FirestoreSchema.backupStops,
      FirestoreSchema.clientSavedAt,
      FirestoreSchema.updatedBy,
      FirestoreSchema.updatedAt,
    });

    final clearing = edit.copy(replaceBackupStops: true, setBackupStops: true, backupStops: const []);
    final clearPatch = ItineraryDayWrite.changedFields(
      existing: existing,
      incoming: clearing,
    );
    expect(clearPatch[FirestoreSchema.backupStops], isEmpty);
  });

  test('修改行程後備選清單保持不變', () async {
    final database = MemoryTripDatabase()..clock = DateTime.utc(2026, 10, 26, 1);
    final connectivity = ConnectivityProbe(isOnline: true);
    final captain = UserAccount(
      id: 'captain',
      email: 'captain@example.com',
      displayName: '隊長',
      birthday: '2000-01-01',
      consentDecided: true,
      analyticsConsent: false,
      crashlyticsConsent: false,
    );
    final local = TripLocalStore(MemoryDocumentStore());
    final remote = MemoryTripRemote(
      database: database,
      currentUserId: () => captain.id,
    );
    final repo = OfflineTripRepository(
      local: local,
      remote: remote,
      currentAccount: () => captain,
      clock: FixedDeviceClock(DateTime.utc(2026, 10, 26, 10)),
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
    await remote.upsertItineraryDay(
      ItineraryDay(
        tripId: trip.id,
        date: '2026-12-01',
        spots: const [ItinerarySpot(name: '清水寺', order: 0, placeId: 'kiyomizu')],
        backupStops: backups,
        replaceBackupStops: true,
        updatedAt: DateTime.utc(2020),
        authorId: captain.id,
      ),
    );

    connectivity.isOnline = false;
    await repo.saveItineraryDay(
      ItineraryDay(
        tripId: trip.id,
        date: '2026-12-01',
        spots: const [ItinerarySpot(name: '伏見稻荷', order: 0, placeId: 'fushimi')],
        backupStops: const [],
        updatedAt: DateTime.utc(2000),
        authorId: 'ignored',
      ),
    );
    connectivity.isOnline = true;
    await repo.sync();

    final stored = database.itinerary[trip.id]!['2026-12-01']!;
    expect(stored.spots.single.name, '伏見稻荷');
    expect(stored.backupStops!.map((spot) => spot.name), ['金閣寺']);
    final shown = await repo.readItineraryDay(trip.id, '2026-12-01');
    expect(shown!.spots.single.name, '伏見稻荷');
    expect(shown.backupStops!.map((spot) => spot.name), ['金閣寺']);
    expect(shown.replaceBackupStops, isFalse);
  });
}
