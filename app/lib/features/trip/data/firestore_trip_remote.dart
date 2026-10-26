import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/data/firestore_schema.dart';
import 'package:group_trip/features/trip/data/firestore_paths.dart';
import 'package:group_trip/features/trip/domain/trip_codec.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/features/trip/domain/trip_repository.dart';

/// Firestore 實作。誰可以讀寫由安全規則決定，用戶端的檢查不是安全邊界。
class FirestoreTripRemote implements TripRemote {
  FirestoreTripRemote({
    required this.currentUserId,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final String Function() currentUserId;

  String get signedInUserId => currentUserId();

  CollectionReference<Map<String, dynamic>> get _trips =>
      _firestore.collection(FirestorePaths.trips);

  CollectionReference<Map<String, dynamic>> get _invites =>
      _firestore.collection(FirestorePaths.inviteCodes);

  @override
  Future<DateTime> serverNow() async {
    final reading = await readServerClock(() async => DateTime.now().toUtc());
    return reading.serverNow;
  }

  /// 寫 `clockProbes/{uid}` 的 `t`，讀回後用手機牆鐘算 offset。
  @override
  Future<ServerClockReading> readServerClock(
    Future<DateTime> Function() deviceNow,
  ) {
    return _guard(() async {
      final uid = signedInUserId;
      if (uid.isEmpty) throw TripAccessDenied();
      final device = (await deviceNow()).toUtc();
      final ref = _firestore.collection(FirestoreSchema.clockProbes).doc(uid);
      await ref.set({FirestoreSchema.probeTime: FieldValue.serverTimestamp()});
      final snap = await ref.get(const GetOptions(source: Source.server));
      final raw = snap.data()?[FirestoreSchema.probeTime];
      if (raw is! Timestamp) {
        throw TripException('讀不到伺服器時間');
      }
      return ServerClockReading(
        serverNow: raw.toDate().toUtc(),
        deviceNow: device,
      );
    });
  }

  @override
  Future<void> upsertTrip(Trip trip) {
    return _guard(() async {
      final ref = _trips.doc(trip.id);
      final existing = await ref.get();
      if (!existing.exists) {
        await ref.set(_tripCreate(trip));
        if (!trip.publicInvite) await ref.update(_closeInvites());
        return;
      }
      final data = existing.data() ?? const <String, dynamic>{};
      if ((data[FirestoreSchema.invitesOpen] == true) != trip.publicInvite) {
        await ref.update(
          trip.publicInvite ? _reopenInvites() : _closeInvites(),
        );
      }
      final remoteAt = _timestampOf(data[FirestoreSchema.expectedReturnAt]);
      final localAt = trip.expectedReturnAt?.toUtc();
      if (!_sameInstant(remoteAt, localAt)) {
        await ref.update({
          FirestoreSchema.expectedReturnAt: _timestamp(localAt),
          FirestoreSchema.updatedAt: FieldValue.serverTimestamp(),
        });
      }
    });
  }

  @override
  Future<Trip?> fetchTrip(String id) {
    return _guard(() async {
      final snap = await _trips.doc(id).get();
      final data = snap.data();
      if (data == null) return null;
      return TripCodec.tripFromMap(_normalize(data), id: id);
    });
  }

  @override
  Future<List<Trip>> fetchTripsForUser(String userId) {
    return _guard(() async {
      final refs = await _firestore
          .collection(FirestorePaths.users)
          .doc(userId)
          .collection(FirestorePaths.tripRefs)
          .get();
      final trips = <Trip>[];
      for (final refDoc in refs.docs) {
        final snap = await _trips.doc(refDoc.id).get();
        final data = snap.data();
        if (data == null) continue;
        trips.add(TripCodec.tripFromMap(_normalize(data), id: snap.id));
      }
      return trips;
    });
  }

  @override
  Future<void> upsertMember(TripMember member) {
    return _guard(() async {
      await _writeMember(member);
      if (member.userId != signedInUserId) return;
      final tripSnap = await _trips.doc(member.tripId).get();
      final title = tripSnap.data()?[FirestoreSchema.title];
      if (title is! String || title.isEmpty) return;
      await _writeTripRef(
        uid: member.userId,
        tripId: member.tripId,
        role: member.role.wire,
        title: title,
      );
    });
  }

  @override
  Future<List<TripMember>> fetchMembers(String tripId) {
    return _guard(() async {
      final query = await _trips
          .doc(tripId)
          .collection(FirestorePaths.members)
          .get();
      return [
        for (final doc in query.docs)
          TripCodec.memberFromMap(
            _normalize(doc.data()),
            userId: doc.id,
            tripId: tripId,
          ),
      ];
    });
  }

  @override
  Future<void> upsertRequest(ModificationRequest request) {
    return _guard(() async {
      final ref = _trips
          .doc(request.tripId)
          .collection(FirestorePaths.requests)
          .doc(request.id);
      final existing = await ref.get();
      final proposed = _timestamp(request.proposedExpectedReturnAt);
      if (!existing.exists) {
        await ref.set({
          FirestoreSchema.type: FirestoreSchema.requestTypeExpectedReturn,
          FirestoreSchema.status: RequestStatus.pending.name,
          FirestoreSchema.proposerId: request.requesterId,
          FirestoreSchema.payload: {FirestoreSchema.expectedReturnAt: proposed},
          FirestoreSchema.createdAt: FieldValue.serverTimestamp(),
          FirestoreSchema.expiresAt: _timestamp(request.expiresAt),
          FirestoreSchema.decidedBy: null,
          FirestoreSchema.decidedAt: null,
        });
        return;
      }
      await ref.update({
        FirestoreSchema.status: request.status.name,
        FirestoreSchema.decidedBy: request.resolvedBy,
        FirestoreSchema.decidedAt: request.resolvedAt == null
            ? null
            : FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<List<ModificationRequest>> fetchRequests(String tripId) {
    return _guard(() async {
      final query = await _trips
          .doc(tripId)
          .collection(FirestorePaths.requests)
          .get();
      return [
        for (final doc in query.docs)
          TripCodec.requestFromMap({
            ..._normalize(doc.data()),
            LocalOnlyFields.documentId: doc.id,
            FirestoreSchema.tripId: tripId,
          }),
      ];
    });
  }

  @override
  Future<void> upsertInvite(InviteRecord invite) {
    return _guard(() async {
      final code = invite.code.trim().toUpperCase();
      final ref = _invites.doc(code);
      final existing = await ref.get();
      if (existing.exists) return;
      await ref.set({
        FirestoreSchema.tripId: invite.tripId,
        FirestoreSchema.tripTitle: invite.tripTitle,
        FirestoreSchema.createdBy: invite.createdBy,
        FirestoreSchema.creatorRole: invite.issuerRole.wire,
        FirestoreSchema.active: true,
        FirestoreSchema.expiresAt: _inviteExpiresAt(),
        FirestoreSchema.createdAt: FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<InviteRecord?> fetchInvite(String code) {
    return _guard(() async {
      final normalized = code.trim().toUpperCase();
      final snap = await _invites.doc(normalized).get();
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return TripCodec.inviteFromMap(_normalize(data), code: normalized);
    });
  }

  @override
  Future<List<InviteRecord>> fetchInvites(String tripId) async {
    // 規則不允許 list invites，所以不能用 tripId 查詢。手機只留自己看過的碼。
    if (tripId.isEmpty) return const [];
    return const [];
  }

  @override
  Future<Trip> join({required String code, required TripMember member}) {
    return _guard(() async {
      final normalized = code.trim().toUpperCase();
      final inviteSnap = await _invites.doc(normalized).get();
      final data = inviteSnap.data();
      if (!inviteSnap.exists || data == null) throw InviteNotFoundException();
      final record = TripCodec.inviteFromMap(
        _normalize(data),
        code: normalized,
      );
      final now = await serverNow();
      if (TripPolicy.isInviteExpired(record.expiresAt, now)) {
        throw InviteExpiredException();
      }
      final tripId = record.tripId;
      try {
        final tripSnap = await _trips.doc(tripId).get();
        final tripData = tripSnap.data();
        if (tripData != null) {
          final trip = TripCodec.tripFromMap(_normalize(tripData), id: tripId);
          if (TripPolicy.memberInviteBlocked(
            invitesResetAt: trip.invitesResetAt,
            issuerRole: record.issuerRole,
            createdAt: record.createdAt,
          )) {
            throw InviteClosedException();
          }
        }
      } on FirebaseException {
        // 還沒加入時通常讀不到旅程，交給下面的成員寫入由規則判斷。
      }
      final memberRef = _trips
          .doc(tripId)
          .collection(FirestorePaths.members)
          .doc(member.userId);
      final existing = await memberRef.get();
      if (existing.exists) throw AlreadyMemberException();
      try {
        await memberRef.set({
          FirestoreSchema.role: FirestoreSchema.roleMember,
          FirestoreSchema.isMinor: member.isMinor,
          FirestoreSchema.displayName: member.displayName,
          FirestoreSchema.photoUrl: member.photoUrl,
          FirestoreSchema.inviteCode: normalized,
          FirestoreSchema.joinedAt: FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied') throw InviteClosedException();
        rethrow;
      }
      final tripSnap = await _trips.doc(tripId).get();
      final tripData = tripSnap.data();
      final title = tripData?[FirestoreSchema.title];
      if (title is String && title.isNotEmpty) {
        await _writeTripRef(
          uid: member.userId,
          tripId: tripId,
          role: FirestoreSchema.roleMember,
          title: title,
        );
      }
      if (tripData == null) {
        throw TripException('已加入旅程，但還讀不到旅程資料。請確認 Firestore 規則允許成員讀取。');
      }
      return TripCodec.tripFromMap(_normalize(tripData), id: tripId);
    });
  }

  @override
  Future<void> upsertItineraryDay(ItineraryDay day) {
    return _guard(() async {
      await _trips
          .doc(day.tripId)
          .collection(FirestorePaths.itinerary)
          .doc(day.date)
          .set({
            FirestoreSchema.date: day.date,
            FirestoreSchema.stops: [
              for (final spot in day.spots) TripCodec.spotToMap(spot),
            ],
            FirestoreSchema.backupStops: const <Map<String, dynamic>>[],
            FirestoreSchema.clientSavedAt: _timestamp(day.updatedAt),
            FirestoreSchema.updatedBy: day.authorId,
            FirestoreSchema.updatedAt: FieldValue.serverTimestamp(),
          });
    });
  }

  @override
  Future<ItineraryDay?> fetchItineraryDay(String tripId, String date) {
    return _guard(() async {
      final snap = await _trips
          .doc(tripId)
          .collection(FirestorePaths.itinerary)
          .doc(date)
          .get();
      final data = snap.data();
      if (data == null) return null;
      return TripCodec.dayFromMap({
        ..._normalize(data),
        FirestoreSchema.tripId: tripId,
      });
    });
  }

  @override
  Future<List<ItineraryDay>> fetchItinerary(String tripId) {
    return _guard(() async {
      final query = await _trips
          .doc(tripId)
          .collection(FirestorePaths.itinerary)
          .get();
      return [
        for (final doc in query.docs)
          TripCodec.dayFromMap({
            ..._normalize(doc.data()),
            FirestoreSchema.tripId: tripId,
          }),
      ];
    });
  }

  @override
  Future<void> upsertRevision(ItineraryRevision revision) {
    return _guard(() async {
      final savedAt = _timestamp(revision.savedAt);
      await _trips
          .doc(revision.tripId)
          .collection(FirestorePaths.itineraryHistory)
          .doc(revision.id)
          .set({
            FirestoreSchema.dayId: revision.date,
            FirestoreSchema.snapshot: {
              FirestoreSchema.stops: [
                for (final spot in revision.spots) TripCodec.spotToMap(spot),
              ],
              FirestoreSchema.backupStops: const <Map<String, dynamic>>[],
              FirestoreSchema.clientSavedAt: savedAt,
              FirestoreSchema.updatedBy: revision.authorId,
            },
            FirestoreSchema.clientSavedAt: savedAt,
            FirestoreSchema.updatedBy: revision.authorId,
            FirestoreSchema.recordedBy: signedInUserId,
            FirestoreSchema.outcome: FirestoreSchema.outcomeSuperseded,
            FirestoreSchema.createdAt: FieldValue.serverTimestamp(),
          });
    });
  }

  @override
  Future<void> upsertLocation(String tripId, LocationSnapshot snapshot) {
    return _guard(() async {
      await _trips
          .doc(tripId)
          .collection(FirestorePaths.locations)
          .doc(snapshot.userId)
          .set({
            FirestoreSchema.latitude: snapshot.latitude,
            FirestoreSchema.longitude: snapshot.longitude,
            FirestoreSchema.sentAt: _timestamp(snapshot.sentAt),
            FirestoreSchema.receivedAt: FieldValue.serverTimestamp(),
            FirestoreSchema.photoUrl: snapshot.photoUrl,
          });
    });
  }

  @override
  Future<List<LocationSnapshot>> fetchLocations(String tripId) {
    return _guard(() async {
      final query = await _trips
          .doc(tripId)
          .collection(FirestorePaths.locations)
          .get();
      return [
        for (final doc in query.docs)
          TripCodec.locationFromMap(_normalize(doc.data()), userId: doc.id),
      ];
    });
  }

  /// 路徑保留給後端規則與後續功能，這一版的畫面還不會寫入。
  DocumentReference<Map<String, dynamic>> handoverRef(String tripId, String id) {
    return _trips.doc(tripId).collection(FirestorePaths.handover).doc(id);
  }

  DocumentReference<Map<String, dynamic>> soloNoticeRef(String tripId, String id) {
    return _trips.doc(tripId).collection(FirestorePaths.soloNotices).doc(id);
  }

  Future<void> _writeMember(TripMember member) async {
    final ref = _trips
        .doc(member.tripId)
        .collection(FirestorePaths.members)
        .doc(member.userId);
    final existing = await ref.get();
    if (!existing.exists) {
      await ref.set({
        FirestoreSchema.role: member.role.wire,
        FirestoreSchema.isMinor: member.isMinor,
        FirestoreSchema.displayName: member.displayName,
        FirestoreSchema.photoUrl: member.photoUrl,
        FirestoreSchema.inviteCode: member.inviteCode,
        FirestoreSchema.joinedAt: FieldValue.serverTimestamp(),
      });
      return;
    }
    final currentRole = existing.data()?[FirestoreSchema.role];
    if (currentRole != member.role.wire) {
      await ref.update({FirestoreSchema.role: member.role.wire});
      return;
    }
    await ref.update({
      FirestoreSchema.displayName: member.displayName,
      FirestoreSchema.photoUrl: member.photoUrl,
      FirestoreSchema.isMinor: member.isMinor,
    });
  }

  Future<void> _writeTripRef({
    required String uid,
    required String tripId,
    required String role,
    required String title,
  }) {
    return _firestore
        .collection(FirestorePaths.users)
        .doc(uid)
        .collection(FirestorePaths.tripRefs)
        .doc(tripId)
        .set({
          FirestoreSchema.tripId: tripId,
          FirestoreSchema.role: role,
          FirestoreSchema.tripTitle: title,
          FirestoreSchema.updatedAt: FieldValue.serverTimestamp(),
        });
  }

  Map<String, dynamic> _tripCreate(Trip trip) {
    final map = TripCodec.tripToMap(trip);
    map[FirestoreSchema.invitesOpen] = true;
    map[FirestoreSchema.invitesResetAt] = null;
    map[FirestoreSchema.expectedReturnAt] = _timestamp(trip.expectedReturnAt);
    map[FirestoreSchema.createdAt] = FieldValue.serverTimestamp();
    map[FirestoreSchema.updatedAt] = FieldValue.serverTimestamp();
    return map;
  }

  Map<String, Object> _closeInvites() => {
    FirestoreSchema.invitesOpen: false,
    FirestoreSchema.invitesResetAt: FieldValue.serverTimestamp(),
    FirestoreSchema.updatedAt: FieldValue.serverTimestamp(),
  };

  Map<String, Object> _reopenInvites() => {
    FirestoreSchema.invitesOpen: true,
    FirestoreSchema.updatedAt: FieldValue.serverTimestamp(),
  };

  /// 規則要求 expiresAt 落在 request.time + 1 小時的前 5 分鐘內。
  Timestamp _inviteExpiresAt() {
    return Timestamp.fromDate(
      DateTime.now().toUtc().add(const Duration(minutes: 58)),
    );
  }

  Timestamp? _timestamp(DateTime? value) =>
      value == null ? null : Timestamp.fromDate(value.toUtc());

  DateTime? _timestampOf(Object? raw) =>
      raw is Timestamp ? raw.toDate().toUtc() : null;

  bool _sameInstant(DateTime? left, DateTime? right) {
    if (left == null || right == null) return left == right;
    return left.toUtc().millisecondsSinceEpoch ==
        right.toUtc().millisecondsSinceEpoch;
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> data) {
    return data.map((key, value) {
      if (value is Timestamp) {
        return MapEntry(key, value.toDate().toUtc().toIso8601String());
      }
      if (value is Map) {
        return MapEntry(key, _normalize(Map<String, dynamic>.from(value)));
      }
      if (value is List) {
        return MapEntry(key, [
          for (final item in value)
            if (item is Map)
              _normalize(Map<String, dynamic>.from(item))
            else
              item,
        ]);
      }
      return MapEntry(key, value);
    });
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on TripException {
      rethrow;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') throw TripAccessDenied();
      throw TripException(error.message ?? 'Firestore 拒絕了這次寫入');
    }
  }
}
