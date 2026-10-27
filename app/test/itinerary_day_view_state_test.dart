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

  testWidgets('超過 staleSnapshotHold 沒有較新或 serverRestored 快照就顯示伺服器目前版本', (
    tester,
  ) async {
    final shown = day(name: '較新的行程', savedAt: newer, authorId: 'other');
    final serverNow = day(
      name: '伺服器上的舊版',
      savedAt: older,
      authorId: 'other',
      placeId: 'old',
    );
    final listener = ItineraryDayListener(
      state: ItineraryDayViewState(localUserId: me, displayed: shown),
      now: () => tester.binding.clock.now(),
    );
    addTearDown(listener.dispose);

    listener.onSnapshot(ItineraryDaySnapshot(day: serverNow));
    expect(listener.state.displayed!.spots.single.name, '較新的行程');
    expect(listener.state.heldSnapshot!.day.spots.single.name, '伺服器上的舊版');

    await tester.pump(
      ItineraryDayViewState.staleSnapshotHold - const Duration(seconds: 1),
    );
    expect(listener.state.displayed!.spots.single.name, '較新的行程');

    await tester.pump(const Duration(seconds: 1));
    expect(listener.state.displayed!.spots.single.name, '伺服器上的舊版');
    expect(listener.state.displayed!.clientSavedAt, older);
    expect(listener.state.serverRestored, isFalse);
    expect(listener.state.heldSnapshot, isNull);
  });

  testWidgets('等待期間若又來較舊快照，時間到了顯示較晚那筆伺服器版本', (tester) async {
    final shown = day(name: '較新的行程', savedAt: newer, authorId: 'other');
    final listener = ItineraryDayListener(
      state: ItineraryDayViewState(localUserId: me, displayed: shown),
      now: () => tester.binding.clock.now(),
    );
    addTearDown(listener.dispose);

    listener.onSnapshot(
      ItineraryDaySnapshot(
        day: day(name: '第一筆舊版', savedAt: older, authorId: 'other', placeId: 'a'),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    listener.onSnapshot(
      ItineraryDaySnapshot(
        day: day(
          name: '伺服器目前版本',
          savedAt: older.add(const Duration(minutes: 30)),
          authorId: 'other',
          placeId: 'b',
        ),
      ),
    );
    expect(listener.state.displayed!.spots.single.name, '較新的行程');
    expect(
      listener.state.heldAt,
      tester.binding.clock.now().toUtc().subtract(const Duration(seconds: 4)),
    );

    await tester.pump(
      ItineraryDayViewState.staleSnapshotHold - const Duration(seconds: 5),
    );
    expect(listener.state.displayed!.spots.single.name, '較新的行程');

    await tester.pump(const Duration(seconds: 1));
    expect(listener.state.displayed!.spots.single.name, '伺服器目前版本');
    expect(listener.state.heldSnapshot, isNull);
  });

  testWidgets('10 秒內收到較新版本或 serverRestored 就不再改去舊快照', (tester) async {
    final shown = day(name: '較新的行程', savedAt: newer, authorId: 'other');
    final listener = ItineraryDayListener(
      state: ItineraryDayViewState(localUserId: me, displayed: shown),
      now: () => tester.binding.clock.now(),
    );
    addTearDown(listener.dispose);

    listener.onSnapshot(
      ItineraryDaySnapshot(
        day: day(name: '暫時的舊版', savedAt: older, authorId: 'other', placeId: 'old'),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    listener.onSnapshot(ItineraryDaySnapshot(day: shown, serverRestored: true));
    await tester.pump(const Duration(seconds: 20));
    expect(listener.state.displayed!.spots.single.name, '較新的行程');
    expect(listener.state.serverRestored, isTrue);
    expect(listener.state.heldSnapshot, isNull);

    final newerStill = day(
      name: '更新的行程',
      savedAt: newer.add(const Duration(hours: 1)),
      authorId: 'other',
      placeId: 'next',
    );
    final another = ItineraryDayListener(
      state: ItineraryDayViewState(localUserId: me, displayed: shown),
      now: () => tester.binding.clock.now(),
    );
    addTearDown(another.dispose);
    another.onSnapshot(
      ItineraryDaySnapshot(
        day: day(name: '暫時的舊版', savedAt: older, authorId: 'other', placeId: 'old'),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    another.onSnapshot(ItineraryDaySnapshot(day: newerStill));
    await tester.pump(const Duration(seconds: 20));
    expect(another.state.displayed!.spots.single.name, '更新的行程');
    expect(another.state.serverRestored, isFalse);
    expect(another.state.heldSnapshot, isNull);
  });
}
