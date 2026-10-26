import 'dart:convert';

import 'package:group_trip/features/trip/domain/trip_models.dart';

/// 行程離線快取允許的欄位。路線、交通時間、地圖圖磚不在這裡。
abstract final class ItineraryCachePolicy {
  static const allowedSpotKeys = {
    'name',
    'order',
    'startTime',
    'endTime',
    'placeId',
    'latitude',
    'longitude',
    'coordinatesCachedAt',
  };

  static const forbiddenKeys = {
    'encodedPolyline',
    'polyline',
    'durationSeconds',
    'travelDuration',
    'route',
    'mapTile',
  };

  static const coordinateRetentionDays = 30;

  static void rejectRouteCache(Map<String, Object?> json) {
    for (final key in json.keys) {
      if (forbiddenKeys.contains(key)) {
        throw ArgumentError('路線、交通時間與地圖圖磚不能進離線快取');
      }
    }
  }

  static bool coordinatesExpired(DateTime cachedAt, DateTime now) {
    final cachedDay = _day(cachedAt);
    final today = _day(now);
    return today.difference(cachedDay).inDays >= coordinateRetentionDays;
  }

  static ItinerarySpot purgeSpot(ItinerarySpot spot, DateTime now) {
    final cachedAt = spot.coordinatesCachedAt;
    final hasPoint = spot.latitude != null || spot.longitude != null;
    if (!hasPoint) return spot;
    if (cachedAt == null || coordinatesExpired(cachedAt, now)) {
      return spot.copy(clearCoordinates: true);
    }
    return spot;
  }

  static ItineraryDay purgeDay(ItineraryDay day, DateTime now) {
    return day.copy(
      spots: [for (final spot in day.spots) purgeSpot(spot, now)],
    );
  }

  static DateTime _day(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }
}

abstract final class TripCodec {
  static Map<String, dynamic> tripToMap(Trip trip) => {
    'id': trip.id,
    'title': trip.title,
    'captainId': trip.captainId,
    'startDate': trip.startDate,
    'endDate': trip.endDate,
    'timeZone': trip.timeZone,
    'expectedReturnAt': trip.expectedReturnAt?.toUtc().toIso8601String(),
    'inviteCode': trip.inviteCode,
    'publicInvite': trip.publicInvite,
    'status': trip.status.wire,
    'memberIds': trip.memberIds,
    'createdAt': trip.createdAt.toUtc().toIso8601String(),
    'updatedAt': trip.updatedAt.toUtc().toIso8601String(),
  };

  static Trip tripFromMap(Map<String, dynamic> map, {String? id}) {
    final memberIds = map['memberIds'];
    return Trip(
      id: id ?? '${map['id']}',
      title: '${map['title']}',
      captainId: '${map['captainId']}',
      startDate: '${map['startDate']}',
      endDate: '${map['endDate']}',
      timeZone: '${map['timeZone']}',
      expectedReturnAt: _instant(map['expectedReturnAt']),
      inviteCode: '${map['inviteCode']}',
      publicInvite: map['publicInvite'] is bool
          ? map['publicInvite'] as bool
          : true,
      status: TripStatus.parse('${map['status']}'),
      memberIds: memberIds is List
          ? [for (final item in memberIds) '$item']
          : const [],
      createdAt: _requiredInstant(map['createdAt']),
      updatedAt: _requiredInstant(map['updatedAt']),
    );
  }

  static Map<String, dynamic> memberToMap(TripMember member) {
    final map = <String, dynamic>{
      'tripId': member.tripId,
      'userId': member.userId,
      'displayName': member.displayName,
      'photoUrl': member.photoUrl,
      'role': member.role.wire,
      'isMinor': member.isMinor,
      'joinedAt': member.joinedAt.toUtc().toIso8601String(),
    };
    assert(!map.containsKey('birthday'));
    return map;
  }

  static TripMember memberFromMap(Map<String, dynamic> map) {
    return TripMember(
      tripId: '${map['tripId']}',
      userId: '${map['userId']}',
      displayName: '${map['displayName']}',
      photoUrl: map['photoUrl'] as String?,
      role: MemberRole.parse('${map['role']}'),
      isMinor: map['isMinor'] == true,
      joinedAt: _requiredInstant(map['joinedAt']),
    );
  }

  static Map<String, dynamic> requestToMap(ModificationRequest request) => {
    'id': request.id,
    'tripId': request.tripId,
    'requesterId': request.requesterId,
    'requesterName': request.requesterName,
    'type': request.type.name,
    'proposedExpectedReturnAt': request.proposedExpectedReturnAt
        .toUtc()
        .toIso8601String(),
    'status': request.status.name,
    'createdAt': request.createdAt.toUtc().toIso8601String(),
    'expiresAt': request.expiresAt?.toUtc().toIso8601String(),
    'resolvedAt': request.resolvedAt?.toUtc().toIso8601String(),
    'resolvedBy': request.resolvedBy,
  };

  static ModificationRequest requestFromMap(Map<String, dynamic> map) {
    return ModificationRequest(
      id: '${map['id']}',
      tripId: '${map['tripId']}',
      requesterId: '${map['requesterId']}',
      requesterName: '${map['requesterName']}',
      type: ModificationType.expectedReturnTime,
      proposedExpectedReturnAt: _requiredInstant(map['proposedExpectedReturnAt']),
      status: RequestStatus.values.firstWhere(
        (status) => status.name == map['status'],
        orElse: () => RequestStatus.pending,
      ),
      createdAt: _requiredInstant(map['createdAt']),
      expiresAt: _instant(map['expiresAt']),
      resolvedAt: _instant(map['resolvedAt']),
      resolvedBy: map['resolvedBy'] as String?,
    );
  }

  static Map<String, dynamic> inviteToMap(InviteRecord invite) => {
    'code': invite.code,
    'tripId': invite.tripId,
    'createdBy': invite.createdBy,
    'createdAt': invite.createdAt.toUtc().toIso8601String(),
    'expiresAt': invite.expiresAt.toUtc().toIso8601String(),
  };

  static InviteRecord inviteFromMap(Map<String, dynamic> map, {String? code}) {
    return InviteRecord(
      code: code ?? '${map['code']}',
      tripId: '${map['tripId']}',
      createdBy: '${map['createdBy'] ?? ''}',
      createdAt: _requiredInstant(map['createdAt']),
      expiresAt: _requiredInstant(map['expiresAt']),
    );
  }

  static Map<String, dynamic> spotToMap(ItinerarySpot spot) {
    final map = <String, dynamic>{
      'name': spot.name,
      'order': spot.order,
      'startTime': spot.startTime,
      'endTime': spot.endTime,
      'placeId': spot.placeId,
      'latitude': spot.latitude,
      'longitude': spot.longitude,
      'coordinatesCachedAt': spot.coordinatesCachedAt?.toUtc().toIso8601String(),
    };
    ItineraryCachePolicy.rejectRouteCache(map);
    return map;
  }

  static ItinerarySpot spotFromMap(Map<String, dynamic> map) {
    return ItinerarySpot(
      name: '${map['name']}',
      order: (map['order'] as num?)?.round() ?? 0,
      startTime: map['startTime'] as String?,
      endTime: map['endTime'] as String?,
      placeId: map['placeId'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      coordinatesCachedAt: _instant(map['coordinatesCachedAt']),
    );
  }

  static Map<String, dynamic> dayToMap(ItineraryDay day) => {
    'tripId': day.tripId,
    'date': day.date,
    'spots': [for (final spot in day.spots) spotToMap(spot)],
    'updatedAt': day.updatedAt.toUtc().toIso8601String(),
    'authorId': day.authorId,
  };

  static ItineraryDay dayFromMap(Map<String, dynamic> map) {
    final spots = map['spots'];
    return ItineraryDay(
      tripId: '${map['tripId']}',
      date: '${map['date']}',
      spots: spots is List
          ? [
              for (final spot in spots)
                if (spot is Map)
                  spotFromMap(Map<String, dynamic>.from(spot)),
            ]
          : const [],
      updatedAt: _requiredInstant(map['updatedAt']),
      authorId: '${map['authorId']}',
    );
  }

  static Map<String, dynamic> revisionToMap(ItineraryRevision revision) => {
    'id': revision.id,
    'tripId': revision.tripId,
    'date': revision.date,
    'spots': [for (final spot in revision.spots) spotToMap(spot)],
    'savedAt': revision.savedAt.toUtc().toIso8601String(),
    'authorId': revision.authorId,
  };

  static ItineraryRevision revisionFromMap(Map<String, dynamic> map) {
    final spots = map['spots'];
    return ItineraryRevision(
      id: '${map['id']}',
      tripId: '${map['tripId']}',
      date: '${map['date']}',
      spots: spots is List
          ? [
              for (final spot in spots)
                if (spot is Map)
                  spotFromMap(Map<String, dynamic>.from(spot)),
            ]
          : const [],
      savedAt: _requiredInstant(map['savedAt']),
      authorId: '${map['authorId']}',
    );
  }

  static Map<String, dynamic> handoverToMap(Handover handover) => {
    'id': handover.id,
    'tripId': handover.tripId,
    'fromUserId': handover.fromUserId,
    'toUserId': handover.toUserId,
    'status': handover.status,
    'createdAt': handover.createdAt.toUtc().toIso8601String(),
  };

  static Handover handoverFromMap(Map<String, dynamic> map) {
    return Handover(
      id: '${map['id']}',
      tripId: '${map['tripId']}',
      fromUserId: '${map['fromUserId']}',
      toUserId: '${map['toUserId']}',
      status: '${map['status']}',
      createdAt: _requiredInstant(map['createdAt']),
    );
  }

  static Map<String, dynamic> soloNoticeToMap(SoloNotice notice) => {
    'id': notice.id,
    'tripId': notice.tripId,
    'userId': notice.userId,
    'expectedBackAt': notice.expectedBackAt.toUtc().toIso8601String(),
    'isMinor': notice.isMinor,
    'approved': notice.approved,
    'createdAt': notice.createdAt.toUtc().toIso8601String(),
  };

  static SoloNotice soloNoticeFromMap(Map<String, dynamic> map) {
    return SoloNotice(
      id: '${map['id']}',
      tripId: '${map['tripId']}',
      userId: '${map['userId']}',
      expectedBackAt: _requiredInstant(map['expectedBackAt']),
      isMinor: map['isMinor'] == true,
      approved: map['approved'] == true,
      createdAt: _requiredInstant(map['createdAt']),
    );
  }

  static Map<String, dynamic> locationToMap(LocationSnapshot snapshot) => {
    'userId': snapshot.userId,
    'latitude': snapshot.latitude,
    'longitude': snapshot.longitude,
    'sentAt': snapshot.sentAt.toUtc().toIso8601String(),
    'photoUrl': snapshot.photoUrl,
  };

  static LocationSnapshot locationFromMap(Map<String, dynamic> map) {
    return LocationSnapshot(
      userId: '${map['userId']}',
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      sentAt: _requiredInstant(map['sentAt']),
      photoUrl: map['photoUrl'] as String?,
    );
  }

  static Map<String, dynamic> syncOpToMap(SyncOp op) => {
    'type': op.type.name,
    'tripId': op.tripId,
    'entityId': op.entityId,
  };

  static SyncOp syncOpFromMap(Map<String, dynamic> map) {
    return SyncOp(
      type: SyncOpType.values.firstWhere((type) => type.name == map['type']),
      tripId: '${map['tripId']}',
      entityId: map['entityId'] as String?,
    );
  }

  static String spotsKey(List<ItinerarySpot> spots) =>
      jsonEncode([for (final spot in spots) spotToMap(spot)]);

  static DateTime _requiredInstant(Object? raw) =>
      _instant(raw) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static DateTime? _instant(Object? raw) {
    if (raw == null || '$raw'.isEmpty || raw == 'null') return null;
    return DateTime.tryParse('$raw')?.toUtc();
  }
}
