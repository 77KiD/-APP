import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/features/trip/domain/trip_codec.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';

void main() {
  test('成員資料沒有生日，旅程可以來回轉換', () {
    final trip = Trip(
      id: 't1',
      title: '京都',
      captainId: 'u1',
      startDate: '2026-11-01',
      endDate: '2026-11-05',
      timeZone: 'Asia/Taipei',
      expectedReturnAt: DateTime.utc(2026, 11, 5, 10),
      inviteCode: 'AB2345',
      status: TripStatus.planning,
      memberIds: const ['u1'],
      createdAt: DateTime.utc(2026, 10, 26),
      updatedAt: DateTime.utc(2026, 10, 26),
    );
    final member = TripMember(
      tripId: 't1',
      userId: 'u1',
      displayName: '隊長',
      role: MemberRole.captain,
      isMinor: false,
      joinedAt: DateTime.utc(2026, 10, 26),
    );
    final memberMap = TripCodec.memberToMap(member);
    expect(memberMap.containsKey('birthday'), isFalse);
    expect(memberMap['role'], 'captain');
    expect(TripCodec.memberFromMap(memberMap).role, MemberRole.captain);
    final restored = TripCodec.tripFromMap(TripCodec.tripToMap(trip));
    expect(restored.expectedReturnAt, trip.expectedReturnAt);
    expect(restored.timeZone, 'Asia/Taipei');
    expect(TripCodec.inviteToMap(tripId: 't1', createdAt: trip.createdAt).keys, {
      'tripId',
      'createdAt',
    });
  });

  test('交接、單獨行動與位置快照的形狀固定', () {
    final handover = TripCodec.handoverFromMap(
      TripCodec.handoverToMap(
        Handover(
          id: 'h1',
          tripId: 't1',
          fromUserId: 'a',
          toUserId: 'b',
          status: 'pending',
          createdAt: DateTime.utc(2026, 10, 26),
        ),
      ),
    );
    expect(handover.toUserId, 'b');
    final notice = TripCodec.soloNoticeFromMap(
      TripCodec.soloNoticeToMap(
        SoloNotice(
          id: 's1',
          tripId: 't1',
          userId: 'a',
          expectedBackAt: DateTime.utc(2026, 11, 1, 9),
          isMinor: true,
          approved: false,
          createdAt: DateTime.utc(2026, 10, 26),
        ),
      ),
    );
    expect(notice.isMinor, isTrue);
    final location = TripCodec.locationToMap(
      LocationSnapshot(
        userId: 'a',
        latitude: 25.0,
        longitude: 121.5,
        sentAt: DateTime.utc(2026, 11, 1),
      ),
    );
    expect(location.containsKey('mapTile'), isFalse);
    expect(location.keys, containsAll(['userId', 'latitude', 'longitude', 'sentAt']));
  });
}
