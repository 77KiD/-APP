import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/data/firestore_schema.dart';
import 'package:group_trip/features/trip/data/firestore_paths.dart';
import 'package:group_trip/features/trip/domain/itinerary_day_write.dart';
import 'package:group_trip/features/trip/domain/trip_codec.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/features/trip/domain/trip_repository.dart';

/// Firestore 實作。誰可以讀寫由安全規則決定，用戶端的檢查不是安全邊界。
class FirestoreTripRemote implements TripRemote {
  FirestoreTripRemote({
    required this.currentUserId,
    FirebaseFirestore? firestore,
    this.joinWriteTimeout = const Duration(seconds: 15),
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final String Function() currentUserId;

  /// 加入時等成員寫入被伺服器確認的上限。
  /// 斷線時 `set` 不會失敗，只會排隊；超過這個時間就當成網路中斷。
  final Duration joinWriteTimeout;

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
  Future<void> flushPendingWrites() {
    return _guard(() => _firestore.waitForPendingWrites());
  }

  @override
  Future<void> upsertTrip(Trip trip) {
    return _guard(() async {
      final ref = _trips.doc(trip.id);
      // 建立直接 set。文件不存在時先 get 會讀到 null 的 resource，規則會拒絕。
      FirebaseException? createDenied;
      try {
        await ref.set(_tripCreate(trip));
        if (!trip.publicInvite) await ref.update(_closeInvites());
        return;
      } on FirebaseException catch (error) {
        if (error.code != 'permission-denied') rethrow;
        createDenied = error;
      }
      final existing = await ref.get();
      if (!existing.exists) throw createDenied;
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
  Future<void> upsertRequest(ModificationRequest request) async {
    // 核准一定要跟旅程一起寫，不能只改申請狀態。
    if (request.status == RequestStatus.approved) {
      try {
        await approveRequest(request);
      } on RequestHandledException {
        // 同步時遇到別人已經決定：以伺服器為準，接下來的讀取會更新手機。
      }
      return;
    }
    return _guard(() async {
      final ref = _requestRef(request);
      final existing = await ref.get();
      if (!existing.exists) {
        await ref.set(_pendingRequest(request));
        // 離線時申請還沒上傳就被拒絕：先建立 pending，再往下寫決定，
        // 不能只建立 pending 就結束，否則決定不會送到伺服器。
        if (request.status == RequestStatus.pending) return;
      } else {
        // 本機仍是 pending 時沒有東西要更新；規則也不允許 pending 改成 pending。
        if (request.status == RequestStatus.pending) return;
        // 伺服器已經有人決定了（例如另一位副隊長），以伺服器為準。
        // 再送一次決定一定會被拒，留在佇列只會卡住後面的同步。
        if (existing.data()?[FirestoreSchema.status] !=
            RequestStatus.pending.name) {
          return;
        }
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
  Future<void> approveRequest(ModificationRequest request) {
    return _guard(() async {
      final tripRef = _trips.doc(request.tripId);
      final ref = _requestRef(request);
      final existing = await ref.get();
      if (!existing.exists) {
        // 離線時還沒上傳就被核准：先建立 pending（規則只讓提出者自己建立）。
        await ref.set(_pendingRequest(request));
      } else if (existing.data()?[FirestoreSchema.status] !=
          RequestStatus.pending.name) {
        throw RequestHandledException();
      }
      // 旅程與申請放在同一個 batch：任一筆被拒，兩筆都不會留下。
      // 規則用 getAfter 核對旅程上的值等於申請內容。
      final batch = _firestore.batch();
      batch.update(tripRef, {
        FirestoreSchema.expectedReturnAt: _timestamp(
          request.proposedExpectedReturnAt,
        ),
        FirestoreSchema.updatedAt: FieldValue.serverTimestamp(),
      });
      batch.update(ref, {
        FirestoreSchema.status: RequestStatus.approved.name,
        FirestoreSchema.decidedBy: request.resolvedBy ?? signedInUserId,
        FirestoreSchema.decidedAt: FieldValue.serverTimestamp(),
      });
      await batch.commit();
    });
  }

  DocumentReference<Map<String, dynamic>> _requestRef(
    ModificationRequest request,
  ) {
    return _trips
        .doc(request.tripId)
        .collection(FirestorePaths.requests)
        .doc(request.id);
  }

  Map<String, Object?> _pendingRequest(ModificationRequest request) => {
    FirestoreSchema.type: FirestoreSchema.requestTypeExpectedReturn,
    FirestoreSchema.status: RequestStatus.pending.name,
    FirestoreSchema.proposerId: request.requesterId,
    FirestoreSchema.payload: {
      FirestoreSchema.expectedReturnAt: _timestamp(
        request.proposedExpectedReturnAt,
      ),
    },
    FirestoreSchema.createdAt: FieldValue.serverTimestamp(),
    FirestoreSchema.expiresAt: _timestamp(request.expiresAt),
    FirestoreSchema.decidedBy: null,
    FirestoreSchema.decidedAt: null,
  };

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
      // 不先讀。效期用手機時間加 1 小時，規則允許相對 request.time 前後 5 分鐘。
      await _invites.doc(code).set({
        FirestoreSchema.tripId: invite.tripId,
        FirestoreSchema.tripTitle: invite.tripTitle,
        FirestoreSchema.createdBy: invite.createdBy,
        FirestoreSchema.creatorRole: invite.issuerRole.wire,
        FirestoreSchema.active: true,
        FirestoreSchema.expiresAt: Timestamp.fromDate(invite.expiresAt.toUtc()),
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
      final DocumentSnapshot<Map<String, dynamic>> inviteSnap;
      try {
        inviteSnap = await _invites.doc(normalized).get();
      } on FirebaseException catch (error) {
        throw _joinUnavailable(error);
      }
      final data = inviteSnap.data();
      if (!inviteSnap.exists || data == null) throw InviteNotFoundException();
      final record = TripCodec.inviteFromMap(
        _normalize(data),
        code: normalized,
      );
      // 規則要求 active == true。先在這裡擋下，免得被拒後誤顯示成公開邀請已關閉。
      if (!record.active) throw InviteExpiredException();
      final DateTime now;
      try {
        now = await serverNow();
      } on TripException {
        throw InvitePermissionException();
      }
      if (TripPolicy.isInviteJoinExpired(
        expiresAt: record.expiresAt,
        createdAt: record.createdAt,
        now: now,
      )) {
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
      try {
        final existing = await memberRef.get();
        if (existing.exists) throw AlreadyMemberException();
      } on FirebaseException catch (error) {
        throw _joinUnavailable(error);
      }
      try {
        await commitJoinMember(memberRef, {
          FirestoreSchema.role: FirestoreSchema.roleMember,
          FirestoreSchema.isMinor: member.isMinor,
          FirestoreSchema.displayName: member.displayName,
          FirestoreSchema.photoUrl: member.photoUrl,
          FirestoreSchema.inviteCode: normalized,
          FirestoreSchema.joinedAt: FieldValue.serverTimestamp(),
        }).timeout(joinWriteTimeout);
      } on TimeoutException {
        debugPrint('join member write timed out after $joinWriteTimeout');
        throw InvitePermissionException();
      } on FirebaseException catch (error) {
        // 外人讀不到旅程，所以關邀請這件事是由規則拒絕這次寫入。
        // creatorRole 在上面的邀請文件裡。只有伺服器明確拒絕，
        // 而且是一般成員的碼，才換成公開邀請已關閉。
        _logFirebase(error);
        // 檢查到寫入之間碼可能剛好過期，這也是 permission-denied。
        if (error.code == 'permission-denied' &&
            await _joinExpiredNow(record)) {
          throw InviteExpiredException();
        }
        throw exceptionForMemberJoinWrite(error, record.issuerRole);
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

  /// 只寫有變動的欄位。沒有 [ItineraryDay.replaceBackupStops] 的更新不會帶
  /// `backupStops`，伺服器上的備選清單維持原樣。建立當天文件時才補上空清單。
  @override
  Future<void> upsertItineraryDay(ItineraryDay day) {
    return _guard(() async {
      final ref = _trips
          .doc(day.tripId)
          .collection(FirestorePaths.itinerary)
          .doc(day.date);
      final snap = await ref.get();
      final data = snap.data();
      final existing = data == null
          ? null
          : TripCodec.dayFromMap({
              ..._normalize(data),
              FirestoreSchema.tripId: day.tripId,
            });
      final patch = ItineraryDayWrite.changedFields(
        existing: existing,
        incoming: day,
      );
      if (patch.isEmpty) return;
      final payload = <String, dynamic>{
        for (final entry in patch.entries)
          entry.key: _encodeItineraryValue(entry.key, entry.value),
      };
      if (existing == null) {
        await ref.set(payload);
      } else {
        await ref.update(payload);
      }
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
  DocumentReference<Map<String, dynamic>> handoverRef(
    String tripId,
    String id,
  ) {
    return _trips.doc(tripId).collection(FirestorePaths.handover).doc(id);
  }

  DocumentReference<Map<String, dynamic>> soloNoticeRef(
    String tripId,
    String id,
  ) {
    return _trips.doc(tripId).collection(FirestorePaths.soloNotices).doc(id);
  }

  Future<void> _writeMember(TripMember member) async {
    final ref = _trips
        .doc(member.tripId)
        .collection(FirestorePaths.members)
        .doc(member.userId);
    // 建立成員也直接 set，不先讀尚未存在的文件。
    FirebaseException? createDenied;
    try {
      await ref.set({
        FirestoreSchema.role: member.role.wire,
        FirestoreSchema.isMinor: member.isMinor,
        FirestoreSchema.displayName: member.displayName,
        FirestoreSchema.photoUrl: member.photoUrl,
        FirestoreSchema.inviteCode: member.inviteCode,
        FirestoreSchema.joinedAt: FieldValue.serverTimestamp(),
      });
      return;
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') rethrow;
      createDenied = error;
    }
    final existing = await ref.get();
    if (!existing.exists) throw createDenied;
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

  Object? _encodeItineraryValue(String key, Object? value) {
    if (key == FirestoreSchema.updatedAt) return FieldValue.serverTimestamp();
    if (value is DateTime) return Timestamp.fromDate(value.toUtc());
    return value;
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

  /// 加入時寫入成員文件。測試可覆寫，用來讓這次寫入遇到真實的斷線。
  Future<void> commitJoinMember(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) {
    return ref.set(data);
  }

  /// 成員寫入失敗時要顯示的錯誤。
  ///
  /// 邀請文件在寫入前已經讀到 [issuerRole]。只有伺服器以
  /// `permission-denied` 拒絕，而且產生者是一般成員，才是公開邀請已關閉。
  /// 斷線、逾時、`unavailable`，或隊長、副隊長的碼被拒絕，維持原本的訊息。
  static TripException exceptionForMemberJoinWrite(
    FirebaseException error,
    MemberRole issuerRole,
  ) {
    if (error.code == 'permission-denied' && issuerRole == MemberRole.member) {
      return InviteClosedException();
    }
    return InvitePermissionException();
  }

  /// 成員寫入被拒後，再用伺服器時間確認一次邀請碼是否已過期。讀不到時間就當沒過期。
  Future<bool> _joinExpiredNow(InviteRecord record) async {
    try {
      final now = await serverNow().timeout(joinWriteTimeout);
      return TripPolicy.isInviteJoinExpired(
        expiresAt: record.expiresAt,
        createdAt: record.createdAt,
        now: now,
      );
    } on Object {
      return false;
    }
  }

  InvitePermissionException _joinUnavailable(FirebaseException error) {
    _logFirebase(error);
    return InvitePermissionException();
  }

  void _logFirebase(FirebaseException error) {
    debugPrint('FirebaseException code=${error.code} message=${error.message}');
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on TripException {
      rethrow;
    } on FirebaseException catch (error) {
      _logFirebase(error);
      if (error.code == 'permission-denied') throw TripAccessDenied();
      throw TripException(error.message ?? 'Firestore 拒絕了這次寫入');
    }
  }
}
