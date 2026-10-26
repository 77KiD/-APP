import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/data/firestore_schema.dart';
import 'package:group_trip/features/trip/domain/trip_codec.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/presentation/itinerary_day_view_state.dart';

void main() {
  const me = 'me';
  final newer = DateTime.utc(2026, 10, 26, 12);
  final older = DateTime.utc(2026, 10, 26, 9);

  ItineraryDay day({
    required String name,
    required DateTime savedAt,
    required String authorId,
    String placeId = 'place',
  }) {
    return ItineraryDay(
      tripId: 'trip',
      date: '2026-12-01',
      spots: [ItinerarySpot(name: name, order: 0, placeId: placeId)],
      updatedAt: savedAt,
      authorId: authorId,
    );
  }

  test('較舊的快照不會換掉畫面上的行程，serverRestored 的較新版本才會', () {
    final shown = day(name: '較新的行程', savedAt: newer, authorId: 'other');
    final state = ItineraryDayViewState(localUserId: me, displayed: shown);
    final stale = ItineraryDaySnapshot.fromMap({
      ...TripCodec.dayToMap(day(name: '暫時出現的舊版', savedAt: older, authorId: 'other')),
      FirestoreSchema.serverRestored: true,
    });
    expect(stale.serverRestored, isTrue);
    expect(stale.day.clientSavedAt, older);

    final kept = state.applySnapshot(stale);
    expect(kept.displayed!.spots.single.name, '較新的行程');
    expect(kept.displayed!.clientSavedAt, newer);
    expect(kept.serverRestored, isFalse);

    final restored = kept.applySnapshot(
      ItineraryDaySnapshot(day: shown, serverRestored: true),
    );
    expect(restored.displayed!.clientSavedAt, newer);
    expect(restored.displayed!.spots.single.name, '較新的行程');
    expect(restored.serverRestored, isTrue);
  });

  test('自己尚未送完的寫入即使 clientSavedAt 比較舊也要更新畫面', () {
    final shown = day(name: '別人的較新版本', savedAt: newer, authorId: 'other');
    final pending = day(name: '我的待上傳', savedAt: older, authorId: me, placeId: 'mine');
    final state = ItineraryDayViewState(
      localUserId: me,
      displayed: shown,
      pendingOwnWrite: pending,
    );

    final someoneElse = state.applySnapshot(
      ItineraryDaySnapshot(
        day: day(name: '別人的舊版', savedAt: older, authorId: 'other', placeId: 'else'),
      ),
    );
    expect(someoneElse.displayed!.spots.single.name, '別人的較新版本');
    expect(someoneElse.pendingOwnWrite, pending);

    final ownEcho = someoneElse.applySnapshot(ItineraryDaySnapshot(day: pending));
    expect(ownEcho.displayed!.spots.single.name, '我的待上傳');
    expect(ownEcho.displayed!.clientSavedAt, older);
    expect(ownEcho.pendingOwnWrite, isNull);

    final optimistic = ItineraryDayViewState(
      localUserId: me,
      displayed: shown,
    ).showPendingOwnWrite(pending);
    expect(optimistic.displayed!.spots.single.name, '我的待上傳');
    expect(optimistic.displayed!.clientSavedAt.isBefore(shown.clientSavedAt), isTrue);
    expect(optimistic.serverRestored, isFalse);
  });
}
