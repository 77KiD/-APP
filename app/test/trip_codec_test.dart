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
    expect(memberMap['role'], 'leader');
    expect(memberMap.containsKey('userId'), isFalse);
    expect(TripCodec.memberFromMap(memberMap).role, MemberRole.captain);
    final wire = TripCodec.tripToMap(trip);
    expect(wire['schemaVersion'], 1);
    expect(wire['leaderId'], 'u1');
    expect(wire.containsKey('captainId'), isFalse);
    expect(wire.containsKey('inviteCode'), isFalse);
    final restored = TripCodec.tripFromMap(wire, id: trip.id);
    expect(restored.expectedReturnAt, trip.expectedReturnAt);
    expect(restored.timeZone, 'Asia/Taipei');
    expect(restored.publicInvite, isTrue);
    expect(restored.captainId, 'u1');
    final invite = InviteRecord(
      code: 'AB2345',
      tripId: 't1',
      tripTitle: '京都',
      createdBy: 'u1',
      issuerRole: MemberRole.captain,
      createdAt: trip.createdAt,
      expiresAt: trip.createdAt.add(const Duration(hours: 1)),
    );
    expect(TripCodec.inviteToMap(invite).keys, {
      'tripId',
      'tripTitle',
      'createdBy',
      'creatorRole',
      'active',
      'createdAt',
      'expiresAt',
    });
    expect(TripCodec.inviteToMap(invite)['creatorRole'], 'leader');
    expect(
      TripCodec.inviteFromMap(TripCodec.inviteToMap(invite)).issuerRole,
      MemberRole.captain,
    );
    expect(
      TripCodec.inviteFromMap(TripCodec.inviteToMap(invite)).expiresAt,
      invite.expiresAt,
    );
    expect(
      TripCodec.tripFromMap({
        ...TripCodec.tripToMap(trip),
        'invitesOpen': false,
      }).publicInvite,
      isFalse,
    );
  });

  test('交接、單獨行動與位置快照的形狀固定', () {
    final handover = TripCodec.handoverFromMap(
      TripCodec.handoverToMap(
        Handover(
          id: 'h1',
          tripId: 't1',
          fromLeaderId: 'a',
          toMemberId: 'b',
          status: 'pending',
          createdAt: DateTime.utc(2026, 10, 26),
        ),
      ),
    );
    expect(handover.toMemberId, 'b');
    expect(handover.rejectionCount, 0);
    final notice = TripCodec.soloNoticeFromMap(
      TripCodec.soloNoticeToMap(
        SoloNotice(
          id: 's1',
          tripId: 't1',
          memberId: 'a',
          expectedBackAt: DateTime.utc(2026, 11, 1, 9),
          isMinor: true,
          status: 'announced',
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
    expect(location.containsKey('userId'), isFalse);
    expect(
      location.keys,
      containsAll(['latitude', 'longitude', 'sentAt', 'receivedAt']),
    );
  });
}
