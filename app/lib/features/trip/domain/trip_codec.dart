import 'dart:convert';

import 'package:group_trip/data/firestore_schema.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';

/// 行程離線快取允許的欄位。路線、交通時間、地圖圖磚不在這裡。
abstract final class ItineraryCachePolicy {
  static const allowedSpotKeys = {
    FirestoreSchema.name,
    FirestoreSchema.order,
    FirestoreSchema.startAt,
    FirestoreSchema.endAt,
    FirestoreSchema.placeId,
    FirestoreSchema.latitude,
    FirestoreSchema.longitude,
    FirestoreSchema.coordinatesCachedAt,
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
  /// Firestore `trips/{tripId}`。沒有邀請碼、成員清單或舊欄位名稱。
  static Map<String, dynamic> tripToMap(Trip trip) => {
    FirestoreSchema.schemaVersion: FirestoreSchema.schemaVersionValue,
    FirestoreSchema.title: trip.title,
    FirestoreSchema.leaderId: trip.captainId,
    FirestoreSchema.status: trip.status.wire,
    FirestoreSchema.startDate: trip.startDate,
    FirestoreSchema.endDate: trip.endDate,
    FirestoreSchema.timeZone: trip.timeZone,
    FirestoreSchema.expectedReturnAt: _iso(trip.expectedReturnAt),
    FirestoreSchema.generalTransport: null,
    FirestoreSchema.returnTransport: null,
    FirestoreSchema.returnFlight: null,
    FirestoreSchema.startedAt: null,
    FirestoreSchema.endedAt: null,
    FirestoreSchema.endReason: null,
    FirestoreSchema.invitesOpen: trip.publicInvite,
    FirestoreSchema.invitesResetAt: _iso(trip.invitesResetAt),
    FirestoreSchema.createdAt: _iso(trip.createdAt),
    FirestoreSchema.updatedAt: _iso(trip.updatedAt),
  };

  static Map<String, dynamic> tripToLocalMap(Trip trip) => {
    ...tripToMap(trip),
    LocalOnlyFields.documentId: trip.id,
    FirestoreSchema.inviteCode: trip.inviteCode,
    LocalOnlyFields.memberIds: trip.memberIds,
  };

  static Trip tripFromMap(Map<String, dynamic> map, {String? id}) {
    final invitesOpen = map[FirestoreSchema.invitesOpen];
    return Trip(
      id: id ?? _string(map[LocalOnlyFields.documentId]),
      title: _string(map[FirestoreSchema.title]),
      captainId: _string(map[FirestoreSchema.leaderId]),
      startDate: _string(map[FirestoreSchema.startDate]),
      endDate: _string(map[FirestoreSchema.endDate]),
      timeZone: _string(map[FirestoreSchema.timeZone]),
      expectedReturnAt: _instant(map[FirestoreSchema.expectedReturnAt]),
      inviteCode: _string(map[FirestoreSchema.inviteCode]),
      publicInvite: invitesOpen is bool ? invitesOpen : true,
      invitesResetAt: _instant(map[FirestoreSchema.invitesResetAt]),
      status: TripStatus.parse(_string(map[FirestoreSchema.status])),
      memberIds: _stringList(map[LocalOnlyFields.memberIds]),
      createdAt: _requiredInstant(map[FirestoreSchema.createdAt]),
      updatedAt: _requiredInstant(map[FirestoreSchema.updatedAt]),
    );
  }

  static Map<String, dynamic> memberToMap(TripMember member) {
    final map = <String, dynamic>{
      FirestoreSchema.role: member.role.wire,
      FirestoreSchema.isMinor: member.isMinor,
      FirestoreSchema.displayName: member.displayName,
      FirestoreSchema.photoUrl: member.photoUrl,
      FirestoreSchema.inviteCode: member.inviteCode,
      FirestoreSchema.joinedAt: _iso(member.joinedAt),
    };
    assert(!map.containsKey(LocalOnlyFields.birthday));
    return map;
  }

  static Map<String, dynamic> memberToLocalMap(TripMember member) => {
    ...memberToMap(member),
    FirestoreSchema.tripId: member.tripId,
    LocalOnlyFields.userId: member.userId,
  };

  static TripMember memberFromMap(
    Map<String, dynamic> map, {
    String? userId,
    String? tripId,
  }) {
    final inviteCode = map[FirestoreSchema.inviteCode];
    return TripMember(
      tripId: tripId ?? _string(map[FirestoreSchema.tripId]),
      userId: userId ?? _string(map[LocalOnlyFields.userId]),
      displayName: _string(map[FirestoreSchema.displayName]),
      photoUrl: map[FirestoreSchema.photoUrl] as String?,
      role: MemberRole.parse(_string(map[FirestoreSchema.role])),
      isMinor: map[FirestoreSchema.isMinor] == true,
      joinedAt: _requiredInstant(map[FirestoreSchema.joinedAt]),
      inviteCode: inviteCode is String ? inviteCode : null,
    );
  }

  static Map<String, dynamic> requestToMap(ModificationRequest request) => {
    FirestoreSchema.type: FirestoreSchema.requestTypeExpectedReturn,
    FirestoreSchema.status: request.status.name,
    FirestoreSchema.proposerId: request.requesterId,
    FirestoreSchema.payload: {
      FirestoreSchema.expectedReturnAt: _iso(request.proposedExpectedReturnAt),
    },
    FirestoreSchema.createdAt: _iso(request.createdAt),
    FirestoreSchema.expiresAt: _iso(request.expiresAt),
    FirestoreSchema.decidedBy: request.resolvedBy,
    FirestoreSchema.decidedAt: _iso(request.resolvedAt),
  };

  static Map<String, dynamic> requestToLocalMap(ModificationRequest request) => {
    ...requestToMap(request),
    LocalOnlyFields.documentId: request.id,
    FirestoreSchema.tripId: request.tripId,
    LocalOnlyFields.requesterName: request.requesterName,
  };

  static ModificationRequest requestFromMap(Map<String, dynamic> map) {
    final payload = map[FirestoreSchema.payload];
    final proposed = payload is Map
        ? payload[FirestoreSchema.expectedReturnAt]
        : map['proposedExpectedReturnAt'];
    return ModificationRequest(
      id: _string(map[LocalOnlyFields.documentId]),
      tripId: _string(map[FirestoreSchema.tripId]),
      requesterId: _string(
        map[FirestoreSchema.proposerId] ?? map['requesterId'],
      ),
      requesterName: _string(map[LocalOnlyFields.requesterName]),
      type: ModificationType.expectedReturnTime,
      proposedExpectedReturnAt: _requiredInstant(proposed),
      status: RequestStatus.values.firstWhere(
        (status) => status.name == map[FirestoreSchema.status],
        orElse: () => RequestStatus.pending,
      ),
      createdAt: _requiredInstant(map[FirestoreSchema.createdAt]),
      expiresAt: _instant(map[FirestoreSchema.expiresAt]),
      resolvedAt: _instant(map[FirestoreSchema.decidedAt] ?? map['resolvedAt']),
      resolvedBy: (map[FirestoreSchema.decidedBy] ?? map['resolvedBy']) as String?,
    );
  }

  static Map<String, dynamic> inviteToMap(InviteRecord invite) => {
    FirestoreSchema.tripId: invite.tripId,
    FirestoreSchema.tripTitle: invite.tripTitle,
    FirestoreSchema.createdBy: invite.createdBy,
    FirestoreSchema.creatorRole: invite.issuerRole.wire,
    FirestoreSchema.active: invite.active,
    FirestoreSchema.createdAt: _iso(invite.createdAt),
    FirestoreSchema.expiresAt: _iso(invite.expiresAt),
  };

  static InviteRecord inviteFromMap(Map<String, dynamic> map, {String? code}) {
    final roleRaw = map[FirestoreSchema.creatorRole] ?? map['issuerRole'];
    return InviteRecord(
      code: code ?? _string(map[FirestoreSchema.inviteCode]),
      tripId: _string(map[FirestoreSchema.tripId]),
      createdBy: _string(map[FirestoreSchema.createdBy]),
      issuerRole: MemberRole.parse(_string(roleRaw)),
      tripTitle: map[FirestoreSchema.tripTitle] is String
          ? map[FirestoreSchema.tripTitle] as String
          : '',
      active: map[FirestoreSchema.active] is bool
          ? map[FirestoreSchema.active] as bool
          : true,
      createdAt: _requiredInstant(map[FirestoreSchema.createdAt]),
      expiresAt: _requiredInstant(map[FirestoreSchema.expiresAt]),
    );
  }

  static Map<String, dynamic> spotToMap(ItinerarySpot spot) {
    final map = <String, dynamic>{
      FirestoreSchema.name: spot.name,
      FirestoreSchema.order: spot.order,
      FirestoreSchema.startAt: spot.startTime,
      FirestoreSchema.endAt: spot.endTime,
      FirestoreSchema.placeId: spot.placeId,
      FirestoreSchema.latitude: spot.latitude,
      FirestoreSchema.longitude: spot.longitude,
      FirestoreSchema.coordinatesCachedAt: _iso(spot.coordinatesCachedAt),
    };
    ItineraryCachePolicy.rejectRouteCache(map);
    return map;
  }

  static ItinerarySpot spotFromMap(Map<String, dynamic> map) {
    return ItinerarySpot(
      name: _string(map[FirestoreSchema.name]),
      order: (map[FirestoreSchema.order] as num?)?.round() ?? 0,
      startTime: _optionalString(
        map[FirestoreSchema.startAt] ?? map[LocalOnlyFields.legacyStartTime],
      ),
      endTime: _optionalString(
        map[FirestoreSchema.endAt] ?? map[LocalOnlyFields.legacyEndTime],
      ),
      placeId: _optionalString(
        map[FirestoreSchema.placeId] ?? map[LocalOnlyFields.legacyPlaceId],
      ),
      latitude: (map[FirestoreSchema.latitude] as num?)?.toDouble(),
      longitude: (map[FirestoreSchema.longitude] as num?)?.toDouble(),
      coordinatesCachedAt: _instant(map[FirestoreSchema.coordinatesCachedAt]),
    );
  }

  static Map<String, dynamic> dayToMap(ItineraryDay day) => {
    FirestoreSchema.date: day.date,
    FirestoreSchema.stops: [for (final spot in day.spots) spotToMap(spot)],
    FirestoreSchema.backupStops: const <Map<String, dynamic>>[],
    FirestoreSchema.clientSavedAt: _iso(day.updatedAt),
    FirestoreSchema.updatedBy: day.authorId,
    FirestoreSchema.updatedAt: _iso(day.updatedAt),
    FirestoreSchema.tripId: day.tripId,
  };

  static ItineraryDay dayFromMap(Map<String, dynamic> map) {
    final spots = map[FirestoreSchema.stops] ?? map['spots'];
    return ItineraryDay(
      tripId: _string(map[FirestoreSchema.tripId]),
      date: _string(map[FirestoreSchema.date] ?? map['date']),
      spots: spots is List
          ? [
              for (final spot in spots)
                if (spot is Map) spotFromMap(Map<String, dynamic>.from(spot)),
            ]
          : const [],
      updatedAt: _requiredInstant(
        map[FirestoreSchema.clientSavedAt] ?? map[FirestoreSchema.updatedAt],
      ),
      authorId: _string(
        map[FirestoreSchema.updatedBy] ?? map[LocalOnlyFields.authorId],
      ),
    );
  }

  static Map<String, dynamic> revisionToMap(ItineraryRevision revision) => {
    LocalOnlyFields.documentId: revision.id,
    FirestoreSchema.tripId: revision.tripId,
    FirestoreSchema.date: revision.date,
    FirestoreSchema.stops: [for (final spot in revision.spots) spotToMap(spot)],
    LocalOnlyFields.savedAt: _iso(revision.savedAt),
    LocalOnlyFields.authorId: revision.authorId,
  };

  static ItineraryRevision revisionFromMap(Map<String, dynamic> map) {
    final spots = map[FirestoreSchema.stops];
    return ItineraryRevision(
      id: _string(map[LocalOnlyFields.documentId]),
      tripId: _string(map[FirestoreSchema.tripId]),
      date: _string(map[FirestoreSchema.date]),
      spots: spots is List
          ? [
              for (final spot in spots)
                if (spot is Map) spotFromMap(Map<String, dynamic>.from(spot)),
            ]
          : const [],
      savedAt: _requiredInstant(map[LocalOnlyFields.savedAt]),
      authorId: _string(map[LocalOnlyFields.authorId]),
    );
  }

  static Map<String, dynamic> handoverToMap(Handover handover) => {
    LocalOnlyFields.documentId: handover.id,
    FirestoreSchema.tripId: handover.tripId,
    FirestoreSchema.fromUserId: handover.fromUserId,
    FirestoreSchema.toUserId: handover.toUserId,
    FirestoreSchema.status: handover.status,
    FirestoreSchema.createdAt: _iso(handover.createdAt),
  };

  static Handover handoverFromMap(Map<String, dynamic> map) {
    return Handover(
      id: _string(map[LocalOnlyFields.documentId]),
      tripId: _string(map[FirestoreSchema.tripId]),
      fromUserId: _string(map[FirestoreSchema.fromUserId]),
      toUserId: _string(map[FirestoreSchema.toUserId]),
      status: _string(map[FirestoreSchema.status]),
      createdAt: _requiredInstant(map[FirestoreSchema.createdAt]),
    );
  }

  static Map<String, dynamic> soloNoticeToMap(SoloNotice notice) => {
    LocalOnlyFields.documentId: notice.id,
    FirestoreSchema.tripId: notice.tripId,
    LocalOnlyFields.userId: notice.userId,
    FirestoreSchema.expectedBackAt: _iso(notice.expectedBackAt),
    FirestoreSchema.isMinor: notice.isMinor,
    FirestoreSchema.approved: notice.approved,
    FirestoreSchema.createdAt: _iso(notice.createdAt),
  };

  static SoloNotice soloNoticeFromMap(Map<String, dynamic> map) {
    return SoloNotice(
      id: _string(map[LocalOnlyFields.documentId]),
      tripId: _string(map[FirestoreSchema.tripId]),
      userId: _string(map[LocalOnlyFields.userId]),
      expectedBackAt: _requiredInstant(map[FirestoreSchema.expectedBackAt]),
      isMinor: map[FirestoreSchema.isMinor] == true,
      approved: map[FirestoreSchema.approved] == true,
      createdAt: _requiredInstant(map[FirestoreSchema.createdAt]),
    );
  }

  static Map<String, dynamic> locationToMap(LocationSnapshot snapshot) => {
    FirestoreSchema.latitude: snapshot.latitude,
    FirestoreSchema.longitude: snapshot.longitude,
    FirestoreSchema.sentAt: _iso(snapshot.sentAt),
    FirestoreSchema.receivedAt: null,
    FirestoreSchema.photoUrl: snapshot.photoUrl,
  };

  static Map<String, dynamic> locationToLocalMap(
    String tripId,
    LocationSnapshot snapshot,
  ) => {
    ...locationToMap(snapshot),
    FirestoreSchema.tripId: tripId,
    LocalOnlyFields.userId: snapshot.userId,
  };

  static LocationSnapshot locationFromMap(
    Map<String, dynamic> map, {
    String? userId,
  }) {
    return LocationSnapshot(
      userId: userId ?? _string(map[LocalOnlyFields.userId]),
      latitude: (map[FirestoreSchema.latitude] as num).toDouble(),
      longitude: (map[FirestoreSchema.longitude] as num).toDouble(),
      sentAt: _requiredInstant(map[FirestoreSchema.sentAt]),
      photoUrl: map[FirestoreSchema.photoUrl] as String?,
    );
  }

  static Map<String, dynamic> syncOpToMap(SyncOp op) => {
    FirestoreSchema.type: op.type.name,
    FirestoreSchema.tripId: op.tripId,
    LocalOnlyFields.documentId: op.entityId,
  };

  static SyncOp syncOpFromMap(Map<String, dynamic> map) {
    final entityId = map[LocalOnlyFields.documentId];
    return SyncOp(
      type: SyncOpType.values.firstWhere(
        (type) => type.name == map[FirestoreSchema.type],
      ),
      tripId: _string(map[FirestoreSchema.tripId]),
      entityId: entityId is String ? entityId : null,
    );
  }

  static String spotsKey(List<ItinerarySpot> spots) =>
      jsonEncode([for (final spot in spots) spotToMap(spot)]);

  static String? _iso(DateTime? value) => value?.toUtc().toIso8601String();

  static String _string(Object? raw) => raw is String ? raw : '';

  static String? _optionalString(Object? raw) => raw is String ? raw : null;

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return [for (final item in raw) '$item'];
  }

  static DateTime _requiredInstant(Object? raw) =>
      _instant(raw) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static DateTime? _instant(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toUtc();
    if (raw is String && raw.isNotEmpty && raw != 'null') {
      return DateTime.tryParse(raw)?.toUtc();
    }
    return null;
  }
}
