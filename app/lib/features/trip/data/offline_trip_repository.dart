import 'package:group_trip/core/ids/id_generator.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/trip/data/trip_local_store.dart';
import 'package:group_trip/features/trip/domain/trip_codec.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/features/trip/domain/trip_repository.dart';
import 'package:group_trip/l10n/app_strings.dart';

class ConnectivityProbe {
  ConnectivityProbe({this.isOnline = true});

  bool isOnline;

  Future<void> refresh() async {}
}

class OfflineTripRepository implements TripRepository {
  OfflineTripRepository({
    required this.local,
    required this.remote,
    required this.currentAccount,
    required this.clock,
    required this.ids,
    required this.connectivity,
  });

  final TripLocalStore local;
  final TripRemote remote;
  final UserAccount? Function() currentAccount;
  final DeviceClock clock;
  final IdGenerator ids;
  final ConnectivityProbe connectivity;

  @override
  Future<Trip> createTrip(NewTripForm form) async {
    final account = _account();
    final now = await _stamp();
    final parsed = TripPolicy.parseNewTrip(form, now);
    if (parsed.error != null) throw ValidationException(parsed.error!);
    final trip = Trip(
      id: ids.next(),
      title: form.title.trim(),
      captainId: account.id,
      startDate: form.startDate.trim(),
      endDate: form.endDate.trim(),
      timeZone: form.timeZone.trim(),
      expectedReturnAt: parsed.expectedReturnAt,
      inviteCode: ids.inviteCode(),
      status: TripStatus.planning,
      memberIds: [account.id],
      createdAt: now,
      updatedAt: now,
    );
    final member = TripMember(
      tripId: trip.id,
      userId: account.id,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
      role: MemberRole.captain,
      isMinor: AgePolicy.isMinor(account.birthday, now),
      joinedAt: now,
    );
    await local.saveTrip(trip);
    await local.saveMember(member);
    await local.saveInvite(
      _issued(
        code: trip.inviteCode,
        tripId: trip.id,
        tripTitle: trip.title,
        createdBy: account.id,
        issuerRole: MemberRole.captain,
        createdAt: now,
      ),
    );
    await local.enqueue(SyncOp(type: SyncOpType.upsertTrip, tripId: trip.id));
    await local.enqueue(
      SyncOp(
        type: SyncOpType.upsertMember,
        tripId: trip.id,
        entityId: account.id,
      ),
    );
    await local.enqueue(
      SyncOp(
        type: SyncOpType.upsertInvite,
        tripId: trip.id,
        entityId: trip.inviteCode,
      ),
    );
    // Critical: trip/member/invite must reach the server. Don't swallow errors.
    if (!connectivity.isOnline) {
      throw ValidationException('建立旅程需要網路。請確認已連線後再試。');
    }
    await sync();
    return (await local.readTrip(trip.id)) ?? trip;
  }

  @override
  Future<Trip> getTrip(String tripId) async {
    final userId = _account().id;
    final cached = await local.readTrip(tripId);
    final cachedMember = await local.isMember(tripId, userId);
    if (!connectivity.isOnline) {
      if (cached != null && cachedMember) return cached;
      throw cached == null
          ? ValidationException(AppStrings.offlineMissing)
          : TripAccessDenied();
    }
    final pendingLocalWrite = await _hasPending(tripId, SyncOpType.upsertTrip);
    if (pendingLocalWrite && cached != null && cachedMember) return cached;
    try {
      final remoteTrip = await remote.fetchTrip(tripId);
      if (remoteTrip == null) {
        if (cached != null && cachedMember) return cached;
        throw TripAccessDenied();
      }
      final members = await remote.fetchMembers(tripId);
      if (!members.any((member) => member.userId == userId)) {
        throw TripAccessDenied();
      }
      if (cached != null &&
          cachedMember &&
          cached.updatedAt.isAfter(remoteTrip.updatedAt)) {
        return cached;
      }
      final merged = _keepDeviceOnlyFields(remoteTrip, cached);
      await local.saveTrip(merged);
      await local.saveMembers(tripId, members);
      await _cacheInvites(remoteTrip.id);
      return merged;
    } on TripAccessDenied {
      if (cached != null && cachedMember) return cached;
      rethrow;
    }
  }

  @override
  Future<List<Trip>> listMyTrips() async {
    if (connectivity.isOnline) await _trySync();
    final userId = _account().id;
    final trips = <Trip>[];
    for (final trip in await local.readAllTrips()) {
      if (await local.isMember(trip.id, userId)) trips.add(trip);
    }
    trips.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return trips;
  }

  @override
  Future<List<TripMember>> listMembers(String tripId) async {
    await getTrip(tripId);
    if (!connectivity.isOnline ||
        await _hasPending(tripId, SyncOpType.upsertMember)) {
      return local.readMembers(tripId);
    }
    try {
      final members = await remote.fetchMembers(tripId);
      await local.saveMembers(tripId, members);
      return members;
    } on TripException {
      return local.readMembers(tripId);
    }
  }

  @override
  Future<Trip> updateExpectedReturnTime({
    required String tripId,
    required DateTime? proposed,
  }) async {
    final trip = await getTrip(tripId);
    final self = await _self(tripId);
    if (!self.role.canEditExpectedReturnDirectly) {
      throw ValidationException(AppStrings.memberMustRequest);
    }
    final now = await _stamp();
    final rejection = TripPolicy.expectedReturnRejection(proposed, now);
    if (rejection != null) throw ValidationException(rejection);
    final updated = trip.copy(
      setExpectedReturn: true,
      expectedReturnAt: proposed,
      updatedAt: now,
    );
    await local.saveTrip(updated);
    await local.enqueue(SyncOp(type: SyncOpType.upsertTrip, tripId: tripId));
    await _trySync();
    return (await local.readTrip(tripId))!;
  }

  @override
  Future<ModificationRequest> submitExpectedReturnRequest({
    required String tripId,
    required DateTime proposed,
  }) async {
    await getTrip(tripId);
    final self = await _self(tripId);
    if (self.role.canEditExpectedReturnDirectly) {
      throw ValidationException(AppStrings.leadersSaveDirectly);
    }
    final now = await _stamp();
    final rejection = TripPolicy.expectedReturnRejection(proposed, now);
    if (rejection != null) throw ValidationException(rejection);
    final members = connectivity.isOnline
        ? await listMembers(tripId)
        : await local.readMembers(tripId);
    final request = ModificationRequest(
      id: ids.next(),
      tripId: tripId,
      requesterId: self.userId,
      requesterName: self.displayName,
      type: ModificationType.expectedReturnTime,
      proposedExpectedReturnAt: proposed,
      status: RequestStatus.pending,
      createdAt: now,
      expiresAt: TripPolicy.requestExpiresAt(
        memberCount: members.length,
        hasViceCaptain: members.any(
          (member) => member.role == MemberRole.viceCaptain,
        ),
        now: now,
      ),
    );
    await local.saveRequest(request);
    await local.enqueue(
      SyncOp(
        type: SyncOpType.upsertRequest,
        tripId: tripId,
        entityId: request.id,
      ),
    );
    await _trySync();
    return request;
  }

  @override
  Future<Trip> approveRequest({
    required String tripId,
    required String requestId,
  }) async {
    final self = await _self(tripId);
    if (!self.role.canEditExpectedReturnDirectly) {
      throw RoleChangeException('只有隊長或副隊長可以同意修改申請');
    }
    return _resolve(
      tripId: tripId,
      requestId: requestId,
      approve: true,
      self: self,
    );
  }

  @override
  Future<ModificationRequest> rejectRequest({
    required String tripId,
    required String requestId,
  }) async {
    final self = await _self(tripId);
    if (!self.role.canEditExpectedReturnDirectly) {
      throw RoleChangeException('只有隊長或副隊長可以拒絕修改申請');
    }
    await _resolve(
      tripId: tripId,
      requestId: requestId,
      approve: false,
      self: self,
    );
    final requests = await local.readRequests(tripId);
    return requests.firstWhere((request) => request.id == requestId);
  }

  Future<Trip> _resolve({
    required String tripId,
    required String requestId,
    required bool approve,
    required TripMember self,
  }) async {
    final trip = await getTrip(tripId);
    final requests = await _loadRequests(tripId);
    final request = requests.cast<ModificationRequest?>().firstWhere(
      (item) => item!.id == requestId,
      orElse: () => null,
    );
    if (request == null) throw ValidationException(AppStrings.requestHandled);
    if (request.status != RequestStatus.pending) {
      throw ValidationException(AppStrings.requestHandled);
    }
    final now = await _stamp();
    if (request.expiresAt != null && !now.isBefore(request.expiresAt!)) {
      await _closeRequest(
        request: request,
        status: RequestStatus.expired,
        now: now,
        self: self,
      );
      throw ValidationException(AppStrings.requestExpired);
    }
    if (!approve) {
      await _closeRequest(
        request: request,
        status: RequestStatus.rejected,
        now: now,
        self: self,
      );
      return trip;
    }
    final rejection = TripPolicy.expectedReturnRejection(
      request.proposedExpectedReturnAt,
      now,
    );
    if (rejection != null) {
      await _closeRequest(
        request: request,
        status: RequestStatus.rejected,
        now: now,
        self: self,
      );
      throw ValidationException(rejection);
    }
    final updated = trip.copy(
      setExpectedReturn: true,
      expectedReturnAt: request.proposedExpectedReturnAt,
      updatedAt: now,
    );
    await local.saveTrip(updated);
    await local.enqueue(SyncOp(type: SyncOpType.upsertTrip, tripId: tripId));
    await _closeRequest(
      request: request,
      status: RequestStatus.approved,
      now: now,
      self: self,
    );
    await _trySync();
    return (await local.readTrip(tripId))!;
  }

  Future<void> _closeRequest({
    required ModificationRequest request,
    required RequestStatus status,
    required DateTime now,
    required TripMember self,
  }) async {
    final closed = request.copy(
      status: status,
      resolvedAt: now,
      resolvedBy: self.userId,
    );
    await local.saveRequest(closed);
    await local.enqueue(
      SyncOp(
        type: SyncOpType.upsertRequest,
        tripId: request.tripId,
        entityId: request.id,
      ),
    );
  }

  @override
  Future<List<ModificationRequest>> listRequests(String tripId) async {
    await getTrip(tripId);
    return _loadRequests(tripId);
  }

  Future<List<ModificationRequest>> _loadRequests(String tripId) async {
    if (connectivity.isOnline &&
        !await _hasPending(tripId, SyncOpType.upsertRequest)) {
      try {
        final remoteRequests = await remote.fetchRequests(tripId);
        await local.saveRequests(tripId, remoteRequests);
      } on TripException {
        // 用手機上已有的申請。
      }
    }
    return local.readRequests(tripId);
  }

  @override
  Future<void> assignViceCaptain({
    required String tripId,
    required String userId,
  }) async {
    final self = await _self(tripId);
    if (self.role != MemberRole.captain) {
      throw RoleChangeException(AppStrings.onlyCaptainAssigns);
    }
    final members = connectivity.isOnline
        ? await listMembers(tripId)
        : await local.readMembers(tripId);
    if (!TripPolicy.canAssignViceCaptain(members.length)) {
      throw RoleChangeException(AppStrings.noViceSmallGroup);
    }
    final target = members.cast<TripMember?>().firstWhere(
      (member) => member!.userId == userId,
      orElse: () => null,
    );
    if (target == null) throw TripAccessDenied();
    if (target.role == MemberRole.captain) {
      throw RoleChangeException(AppStrings.cannotDemoteCaptain);
    }
    for (final member in members) {
      if (member.role == MemberRole.viceCaptain && member.userId != userId) {
        final demoted = member.copy(role: MemberRole.member);
        await local.saveMember(demoted);
        await local.enqueue(
          SyncOp(
            type: SyncOpType.upsertMember,
            tripId: tripId,
            entityId: demoted.userId,
          ),
        );
      }
    }
    await local.saveMember(target.copy(role: MemberRole.viceCaptain));
    await local.enqueue(
      SyncOp(type: SyncOpType.upsertMember, tripId: tripId, entityId: userId),
    );
    await _trySync();
  }

  @override
  Future<Trip> joinWithInviteCode(String rawCode) async {
    final account = _account();
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty) throw ValidationException(AppStrings.emptyInvite);
    if (!connectivity.isOnline) {
      throw ValidationException(AppStrings.joinNeedsNetwork);
    }
    final now = await _stamp();
    final trip = await remote.join(
      code: code,
      member: TripMember(
        tripId: '',
        userId: account.id,
        displayName: account.displayName,
        photoUrl: account.photoUrl,
        role: MemberRole.member,
        isMinor: AgePolicy.isMinor(account.birthday, now),
        joinedAt: now,
      ),
    );
    final members = await remote.fetchMembers(trip.id);
    await local.saveTrip(trip);
    await local.saveMembers(trip.id, members);
    await _cacheInvites(trip.id);
    final used = await remote.fetchInvite(code);
    if (used != null) await local.saveInvite(used);
    return trip;
  }

  @override
  Future<InviteRecord> issueInviteCode(String tripId) async {
    final account = _account();
    final trip = await getTrip(tripId);
    if (connectivity.isOnline) {
      try {
        final members = await remote.fetchMembers(tripId);
        await local.saveMembers(tripId, members);
      } on TripException {
        // 用手機上已有的成員角色判斷。
      }
    }
    final self = await _self(tripId);
    if (!TripPolicy.canIssueInvite(
      role: self.role,
      publicInvite: trip.publicInvite,
    )) {
      throw RoleChangeException(AppStrings.cannotIssueInvite);
    }
    final now = await _stamp();
    final invite = _issued(
      code: await _freshCode(),
      tripId: trip.id,
      tripTitle: trip.title,
      createdBy: account.id,
      issuerRole: self.role,
      createdAt: now,
    );
    await local.saveInvite(invite);
    await local.enqueue(
      SyncOp(
        type: SyncOpType.upsertInvite,
        tripId: trip.id,
        entityId: invite.code,
      ),
    );
    // Critical: invite must reach the server. Don't swallow errors.
    if (!connectivity.isOnline) {
      throw ValidationException('產生邀請碼需要網路。請確認已連線後再試。');
    }
    await sync();
    return (await local.readInvite(invite.code)) ?? invite;
  }

  @override
  Future<Trip> setPublicInvite({
    required String tripId,
    required bool enabled,
  }) async {
    final trip = await getTrip(tripId);
    final self = await _self(tripId);
    if (!TripPolicy.canTogglePublicInvite(self.role)) {
      throw RoleChangeException(AppStrings.onlyLeadersSetPublicInvite);
    }
    if (trip.publicInvite == enabled) return trip;
    final now = await _stamp();
    final DateTime? resetAt;
    if (!enabled) {
      final server = connectivity.isOnline ? await remote.serverNow() : now;
      // 測試時鐘常常凍在邀請碼的 createdAt。規則是 createdAt >= invitesResetAt
      // 仍算有效，而真正的關閉會用較晚的 request.time。這裡把記憶體裡的
      // 截止時間往後 1 微秒，已經存在的一般成員碼才會立刻失效。
      // Firestore 寫入用 FieldValue.serverTimestamp()，不採用這 1 微秒。
      resetAt = server.toUtc().add(const Duration(microseconds: 1));
    } else {
      resetAt = trip.invitesResetAt;
    }
    final updated = trip.copy(
      publicInvite: enabled,
      setInvitesResetAt: true,
      invitesResetAt: resetAt,
      updatedAt: now,
    );
    await local.saveTrip(updated);
    await local.enqueue(SyncOp(type: SyncOpType.upsertTrip, tripId: tripId));
    await _trySync();
    return (await local.readTrip(tripId)) ?? updated;
  }

  @override
  Future<List<InviteRecord>> listInvites(String tripId) async {
    await getTrip(tripId);
    if (connectivity.isOnline) await _cacheInvites(tripId);
    final invites = await local.readInvites(tripId);
    invites.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return invites;
  }

  @override
  Future<void> saveItineraryDay(ItineraryDay day) async {
    await getTrip(day.tripId);
    final now = await _stamp();
    final purged = ItineraryCachePolicy.purgeDay(
      day.copy(updatedAt: now, authorId: _account().id),
      now,
    );
    await local.saveItineraryDay(purged);
    await local.enqueue(
      SyncOp(
        type: SyncOpType.upsertItinerary,
        tripId: day.tripId,
        entityId: day.date,
      ),
    );
    await _trySync();
  }

  @override
  Future<ItineraryDay?> readItineraryDay(String tripId, String date) async {
    await getTrip(tripId);
    final now = await _stamp();
    final day = await local.readItineraryDay(tripId, date);
    if (day == null) return null;
    final purged = ItineraryCachePolicy.purgeDay(day, now);
    if (TripCodec.spotsKey(day.spots) != TripCodec.spotsKey(purged.spots) ||
        TripCodec.spotsKey(day.backupStops ?? const []) !=
            TripCodec.spotsKey(purged.backupStops ?? const [])) {
      await local.saveItineraryDay(purged);
    }
    return purged;
  }

  @override
  Future<List<ItineraryRevision>> readItineraryRevisions(
    String tripId,
    String date,
  ) async {
    await getTrip(tripId);
    return local.readRevisions(tripId, date);
  }

  @override
  Future<void> saveLastKnownLocation(
    String tripId,
    LocationSnapshot snapshot,
  ) async {
    await getTrip(tripId);
    await local.saveLocation(tripId, snapshot);
    await local.enqueue(
      SyncOp(
        type: SyncOpType.upsertLocation,
        tripId: tripId,
        entityId: snapshot.userId,
      ),
    );
    await _trySync();
  }

  @override
  Future<List<LocationSnapshot>> readLastKnownLocations(String tripId) async {
    await getTrip(tripId);
    if (!connectivity.isOnline) return local.readLocations(tripId);
    try {
      final remoteLocations = await remote.fetchLocations(tripId);
      for (final snapshot in remoteLocations) {
        await local.saveLocation(tripId, snapshot);
      }
      return await local.readLocations(tripId);
    } on TripException {
      return local.readLocations(tripId);
    }
  }

  @override
  Future<void> sync() async {
    if (!connectivity.isOnline) return;
    final queue = await local.readQueue();
    for (final op in queue) {
      // 行程改由 _mergeItinerary 比較校正後的儲存時間，避免先蓋掉另一台手機的版本。
      if (op.type == SyncOpType.upsertItinerary) continue;
      await _push(op);
      await local.removeOp(op);
    }
    await _pull();
    for (final op in await local.readQueue()) {
      if (op.type == SyncOpType.upsertItinerary) await local.removeOp(op);
    }
    // 佇列裡的 clientSavedAt 沿用送出前的樣本。新的時鐘差等離線寫入送完才記下，
    // 而且只留在手機上，不寫 syncAnchors。
    await remote.flushPendingWrites();
    await _recordTimeSample();
  }

  Future<void> _trySync() async {
    if (!connectivity.isOnline) return;
    try {
      await sync();
    } on TripException {
      // 已經寫進手機。連線恢復後再送。
    }
  }

  Future<void> _recordTimeSample() async {
    final reading = await remote.readServerClock(clock.now);
    final elapsed = await clock.elapsedRealtime();
    await local.saveTimeSample(
      TimeSample(
        serverNow: reading.serverNow.toUtc(),
        deviceNow: reading.deviceNow.toUtc(),
        elapsedRealtime: elapsed,
      ),
    );
  }

  Future<DateTime> _stamp() async {
    return CorrectedClock.stamp(
      sample: await local.readTimeSample(),
      deviceNow: await clock.now(),
      elapsedRealtime: await clock.elapsedRealtime(),
    );
  }

  Future<void> _push(SyncOp op) async {
    switch (op.type) {
      case SyncOpType.upsertTrip:
        final trip = await local.readTrip(op.tripId);
        if (trip != null) await remote.upsertTrip(trip);
      case SyncOpType.upsertMember:
        final members = await local.readMembers(op.tripId);
        for (final member in members) {
          if (op.entityId == null || member.userId == op.entityId) {
            await remote.upsertMember(member);
          }
        }
      case SyncOpType.upsertRequest:
        final requests = await local.readRequests(op.tripId);
        for (final request in requests) {
          if (op.entityId == null || request.id == op.entityId) {
            await remote.upsertRequest(request);
          }
        }
      case SyncOpType.upsertInvite:
        final trip = await local.readTrip(op.tripId);
        final code = op.entityId ?? trip?.inviteCode;
        if (code != null) {
          final invite = await local.readInvite(code);
          if (invite != null) await remote.upsertInvite(invite);
        }
      case SyncOpType.upsertItinerary:
        final day = await local.readItineraryDay(op.tripId, op.entityId ?? '');
        if (day != null) await remote.upsertItineraryDay(day);
      case SyncOpType.upsertRevision:
        final revisions = await local.readRevisions(
          op.tripId,
          op.entityId ?? '',
        );
        for (final revision in revisions) {
          await remote.upsertRevision(revision);
        }
      case SyncOpType.upsertLocation:
        final locations = await local.readLocations(op.tripId);
        for (final snapshot in locations) {
          if (op.entityId == null || snapshot.userId == op.entityId) {
            await remote.upsertLocation(op.tripId, snapshot);
          }
        }
    }
  }

  Future<void> _pull() async {
    final userId = _account().id;
    final remoteTrips = await remote.fetchTripsForUser(userId);
    for (final remoteTrip in remoteTrips) {
      final cached = await local.readTrip(remoteTrip.id);
      if (cached != null && cached.updatedAt.isAfter(remoteTrip.updatedAt)) {
        await remote.upsertTrip(cached);
        for (final member in await local.readMembers(remoteTrip.id)) {
          await remote.upsertMember(member);
        }
        for (final request in await local.readRequests(remoteTrip.id)) {
          await remote.upsertRequest(request);
        }
      } else {
        await local.saveTrip(_keepDeviceOnlyFields(remoteTrip, cached));
        await _cacheInvites(remoteTrip.id);
        await local.saveMembers(
          remoteTrip.id,
          await remote.fetchMembers(remoteTrip.id),
        );
        await local.saveRequests(
          remoteTrip.id,
          await remote.fetchRequests(remoteTrip.id),
        );
      }
      await _mergeItinerary(remoteTrip.id);
      final remoteLocations = await remote.fetchLocations(remoteTrip.id);
      for (final snapshot in remoteLocations) {
        await local.saveLocation(remoteTrip.id, snapshot);
      }
    }
  }

  /// Firestore 旅程文件沒有邀請碼和成員清單。讀回來時保留手機上的那兩欄。
  Trip _keepDeviceOnlyFields(Trip remoteTrip, Trip? cached) {
    if (cached == null || cached.id != remoteTrip.id) return remoteTrip;
    final inviteCode = remoteTrip.inviteCode.isNotEmpty
        ? remoteTrip.inviteCode
        : cached.inviteCode;
    final memberIds = remoteTrip.memberIds.isNotEmpty
        ? remoteTrip.memberIds
        : cached.memberIds;
    if (inviteCode == remoteTrip.inviteCode &&
        _sameIds(memberIds, remoteTrip.memberIds)) {
      return remoteTrip;
    }
    return remoteTrip.copy(inviteCode: inviteCode, memberIds: memberIds);
  }

  bool _sameIds(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  InviteRecord _issued({
    required String code,
    required String tripId,
    required String tripTitle,
    required String createdBy,
    required MemberRole issuerRole,
    required DateTime createdAt,
  }) {
    return InviteRecord(
      code: code.trim().toUpperCase(),
      tripId: tripId,
      tripTitle: tripTitle,
      createdBy: createdBy,
      issuerRole: issuerRole,
      createdAt: createdAt.toUtc(),
      expiresAt: TripPolicy.inviteExpiresAt(createdAt),
    );
  }

  Future<String> _freshCode() async {
    for (var guard = 0; guard < 5; guard++) {
      final code = ids.inviteCode().trim().toUpperCase();
      if (await local.readInvite(code) != null) continue;
      if (!connectivity.isOnline) return code;
      try {
        if (await remote.fetchInvite(code) == null) return code;
      } on TripException {
        return code;
      }
    }
    return ids.inviteCode().trim().toUpperCase();
  }

  Future<void> _cacheInvites(String tripId) async {
    try {
      for (final invite in await remote.fetchInvites(tripId)) {
        await local.saveInvite(invite);
      }
    } on TripException {
      // 旅程資料仍可用。邀請碼剩餘時間等下次連線再補。
    }
  }

  Future<bool> _hasPending(String tripId, SyncOpType type) async {
    final queue = await local.readQueue();
    return queue.any((op) => op.tripId == tripId && op.type == type);
  }

  Future<void> _mergeItinerary(String tripId) async {
    final dates = <String>{
      for (final day in await local.readItinerary(tripId)) day.date,
    };
    try {
      for (final day in await remote.fetchItinerary(tripId)) {
        dates.add(day.date);
      }
    } on TripException {
      // 沒有遠端行程時，只保留手機上的版本。
    }
    for (final date in dates) {
      final cached = await local.readItineraryDay(tripId, date);
      ItineraryDay? remoteDay;
      try {
        remoteDay = await remote.fetchItineraryDay(tripId, date);
      } on TripException {
        remoteDay = null;
      }
      if (cached == null) {
        if (remoteDay != null) await local.saveItineraryDay(remoteDay);
        continue;
      }
      if (remoteDay == null || cached.updatedAt.isAfter(remoteDay.updatedAt)) {
        if (remoteDay != null &&
            TripCodec.spotsKey(remoteDay.spots) !=
                TripCodec.spotsKey(cached.spots)) {
          await _keepLoser(remoteDay);
        }
        await remote.upsertItineraryDay(cached);
        try {
          final saved = await remote.fetchItineraryDay(tripId, date);
          if (saved != null) await local.saveItineraryDay(saved);
        } on TripException {
          // 遠端已保留備選清單。本機等下次讀得到再補。
        }
      } else if (TripCodec.spotsKey(remoteDay.spots) !=
          TripCodec.spotsKey(cached.spots)) {
        await _keepLoser(cached);
        await local.saveItineraryDay(remoteDay);
      }
    }
  }

  Future<void> _keepLoser(ItineraryDay day) async {
    final revision = ItineraryRevision(
      id: ids.next(),
      tripId: day.tripId,
      date: day.date,
      spots: day.spots,
      savedAt: day.updatedAt,
      authorId: day.authorId,
    );
    await local.saveRevision(revision);
    await remote.upsertRevision(revision);
  }

  UserAccount _account() {
    final account = currentAccount();
    if (account == null) throw TripAccessDenied();
    return account;
  }

  Future<TripMember> _self(String tripId) async {
    final userId = _account().id;
    final members = await local.readMembers(tripId);
    for (final member in members) {
      if (member.userId == userId) return member;
    }
    throw TripAccessDenied();
  }
}
