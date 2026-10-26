import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/features/trip/domain/trip_codec.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';

void main() {
  test('離線快取只留行程欄位，不留路線與交通時間', () {
    expect(
      () => ItineraryCachePolicy.rejectRouteCache({
        'encodedPolyline': 'abc',
      }),
      throwsArgumentError,
    );
    final map = TripCodec.spotToMap(
      const ItinerarySpot(name: '清水寺', order: 1, placeId: 'place-1'),
    );
    expect(map.keys, ItineraryCachePolicy.allowedSpotKeys);
    expect(map.keys, isNot(contains('durationSeconds')));
  });

  test('座標滿 30 個日曆日就刪除，place_id 與名稱還在', () {
    final cached = DateTime.utc(2026, 1, 1, 8);
    final spot = ItinerarySpot(
      name: '清水寺',
      order: 1,
      placeId: 'place-1',
      latitude: 34.99,
      longitude: 135.78,
      coordinatesCachedAt: cached,
    );
    final day = ItineraryDay(
      tripId: 't1',
      date: '2026-01-01',
      spots: [spot],
      updatedAt: cached,
      authorId: 'u1',
    );
    final kept = ItineraryCachePolicy.purgeDay(day, DateTime.utc(2026, 1, 30));
    expect(kept.spots.single.latitude, 34.99);
    expect(kept.spots.single.placeId, 'place-1');
    final purged = ItineraryCachePolicy.purgeDay(
      day,
      DateTime.utc(2026, 1, 31),
    );
    expect(purged.spots.single.latitude, isNull);
    expect(purged.spots.single.longitude, isNull);
    expect(purged.spots.single.placeId, 'place-1');
    expect(purged.spots.single.name, '清水寺');
  });

  test('讀回時丟掉不該快取的路線欄位', () {
    final spot = TripCodec.spotFromMap({
      'name': '清水寺',
      'order': 1,
      'placeId': 'place-1',
      'encodedPolyline': 'should-drop',
      'durationSeconds': 120,
    });
    expect(TripCodec.spotToMap(spot).containsKey('encodedPolyline'), isFalse);
    expect(spot.placeId, 'place-1');
  });
}
