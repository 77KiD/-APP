import 'package:group_trip/data/firestore_schema.dart';
import 'package:group_trip/l10n/app_strings.dart';

enum MemberRole {
  captain,
  viceCaptain,
  member;

  String get label => switch (this) {
    MemberRole.captain => AppStrings.roleCaptain,
    MemberRole.viceCaptain => AppStrings.roleVice,
    MemberRole.member => AppStrings.roleMember,
  };

  /// 寫進 Firestore 的角色。畫面仍是隊長、副隊長、一般成員。
  String get wire => switch (this) {
    MemberRole.captain => FirestoreSchema.roleLeader,
    MemberRole.viceCaptain => FirestoreSchema.roleDeputy,
    MemberRole.member => FirestoreSchema.roleMember,
  };

  static MemberRole parse(String raw) {
    return switch (raw) {
      FirestoreSchema.roleLeader ||
      LocalOnlyFields.legacyRoleCaptain => MemberRole.captain,
      FirestoreSchema.roleDeputy ||
      LocalOnlyFields.legacyRoleDeputy => MemberRole.viceCaptain,
      _ => MemberRole.member,
    };
  }

  bool get canEditExpectedReturnDirectly =>
      this == MemberRole.captain || this == MemberRole.viceCaptain;
}

enum TripStatus {
  planning,
  active,
  ended;

  String get wire => name;

  static TripStatus parse(String raw) {
    return TripStatus.values.firstWhere(
      (status) => status.wire == raw,
      orElse: () => TripStatus.planning,
    );
  }
}

class Trip {
  const Trip({
    required this.id,
    required this.title,
    required this.captainId,
    required this.startDate,
    required this.endDate,
    required this.timeZone,
    required this.expectedReturnAt,
    required this.inviteCode,
    this.publicInvite = true,
    this.invitesResetAt,
    required this.status,
    required this.memberIds,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String captainId;
  final String startDate;
  final String endDate;
  final String timeZone;
  final DateTime? expectedReturnAt;
  final String inviteCode;

  /// 對應 Firestore `invitesOpen`。預設開啟。
  final bool publicInvite;

  /// 關掉公開邀請時寫下的截止時間。再打開時保留，一般成員較早的碼不會恢復。
  final DateTime? invitesResetAt;
  final TripStatus status;
  final List<String> memberIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  Trip copy({
    DateTime? updatedAt,
    List<String>? memberIds,
    TripStatus? status,
    String? inviteCode,
    bool? publicInvite,
    bool setInvitesResetAt = false,
    DateTime? invitesResetAt,
    bool setExpectedReturn = false,
    DateTime? expectedReturnAt,
  }) {
    return Trip(
      id: id,
      title: title,
      captainId: captainId,
      startDate: startDate,
      endDate: endDate,
      timeZone: timeZone,
      expectedReturnAt: setExpectedReturn
          ? expectedReturnAt
          : this.expectedReturnAt,
      inviteCode: inviteCode ?? this.inviteCode,
      publicInvite: publicInvite ?? this.publicInvite,
      invitesResetAt: setInvitesResetAt ? invitesResetAt : this.invitesResetAt,
      status: status ?? this.status,
      memberIds: memberIds ?? this.memberIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class TripMember {
  const TripMember({
    required this.tripId,
    required this.userId,
    required this.displayName,
    required this.role,
    required this.isMinor,
    required this.joinedAt,
    this.photoUrl,
    this.inviteCode,
  });

  final String tripId;
  final String userId;
  final String displayName;
  final String? photoUrl;
  final MemberRole role;
  final bool isMinor;
  final DateTime joinedAt;

  /// 隊長是 null。加入的人是當時使用的邀請碼。
  final String? inviteCode;

  TripMember copy({MemberRole? role}) {
    return TripMember(
      tripId: tripId,
      userId: userId,
      displayName: displayName,
      photoUrl: photoUrl,
      role: role ?? this.role,
      isMinor: isMinor,
      joinedAt: joinedAt,
      inviteCode: inviteCode,
    );
  }
}

enum ModificationType { expectedReturnTime }

enum RequestStatus { pending, approved, rejected, expired }

class ModificationRequest {
  const ModificationRequest({
    required this.id,
    required this.tripId,
    required this.requesterId,
    required this.requesterName,
    required this.type,
    required this.proposedExpectedReturnAt,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.resolvedAt,
    this.resolvedBy,
  });

  final String id;
  final String tripId;
  final String requesterId;
  final String requesterName;
  final ModificationType type;
  final DateTime proposedExpectedReturnAt;
  final RequestStatus status;
  final DateTime createdAt;

  /// 5–7 人且沒有副隊長時為 null，申請會留到隊長或副隊長回應。
  final DateTime? expiresAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;

  ModificationRequest copy({
    RequestStatus? status,
    DateTime? resolvedAt,
    String? resolvedBy,
  }) {
    return ModificationRequest(
      id: id,
      tripId: tripId,
      requesterId: requesterId,
      requesterName: requesterName,
      type: type,
      proposedExpectedReturnAt: proposedExpectedReturnAt,
      status: status ?? this.status,
      createdAt: createdAt,
      expiresAt: expiresAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolvedBy: resolvedBy ?? this.resolvedBy,
    );
  }
}

class ItinerarySpot {
  const ItinerarySpot({
    required this.name,
    required this.order,
    this.startTime,
    this.endTime,
    this.placeId,
    this.latitude,
    this.longitude,
    this.coordinatesCachedAt,
  });

  final String name;
  final int order;
  final String? startTime;
  final String? endTime;
  final String? placeId;
  final double? latitude;
  final double? longitude;
  final DateTime? coordinatesCachedAt;

  ItinerarySpot copy({
    double? latitude,
    double? longitude,
    DateTime? coordinatesCachedAt,
    bool clearCoordinates = false,
  }) {
    return ItinerarySpot(
      name: name,
      order: order,
      startTime: startTime,
      endTime: endTime,
      placeId: placeId,
      latitude: clearCoordinates ? null : latitude ?? this.latitude,
      longitude: clearCoordinates ? null : longitude ?? this.longitude,
      coordinatesCachedAt: clearCoordinates
          ? null
          : coordinatesCachedAt ?? this.coordinatesCachedAt,
    );
  }
}

class ItineraryDay {
  const ItineraryDay({
    required this.tripId,
    required this.date,
    required this.spots,
    required this.updatedAt,
    required this.authorId,
    this.backupStops,
    this.replaceBackupStops = false,
  });

  final String tripId;
  final String date;
  final List<ItinerarySpot> spots;

  /// 備選清單。null 表示這份資料沒有帶清單。
  /// 更新時是否寫進 Firestore 看 [replaceBackupStops]，不是看這份清單是不是空的。
  final List<ItinerarySpot>? backupStops;

  /// true 才在更新時覆寫備選清單（包含明確清空）。修改行程內容時維持 false。
  final bool replaceBackupStops;

  final DateTime updatedAt;

  /// 校正後的儲存時間。對應 Firestore `clientSavedAt`，不是伺服器收到的 `updatedAt`。
  DateTime get clientSavedAt => updatedAt;

  final String authorId;

  ItineraryDay copy({
    List<ItinerarySpot>? spots,
    List<ItinerarySpot>? backupStops,
    bool setBackupStops = false,
    bool? replaceBackupStops,
    DateTime? updatedAt,
    String? authorId,
  }) {
    return ItineraryDay(
      tripId: tripId,
      date: date,
      spots: spots ?? this.spots,
      backupStops: setBackupStops ? backupStops : this.backupStops,
      replaceBackupStops: replaceBackupStops ?? this.replaceBackupStops,
      updatedAt: updatedAt ?? this.updatedAt,
      authorId: authorId ?? this.authorId,
    );
  }
}

/// 被覆蓋的行程版本，例如 `trips/{tripId}/itineraryHistory`。
/// 帳號刪除後，修改紀錄裡的個人內容會改顯示「已刪除的成員」。
class ItineraryRevision {
  const ItineraryRevision({
    required this.id,
    required this.tripId,
    required this.date,
    required this.spots,
    required this.savedAt,
    required this.authorId,
  });

  final String id;
  final String tripId;
  final String date;
  final List<ItinerarySpot> spots;
  final DateTime savedAt;
  final String authorId;
}

/// `trips/{tripId}/handover`。這一版只定義形狀，交接流程不在 #3。
class Handover {
  const Handover({
    required this.id,
    required this.tripId,
    required this.fromLeaderId,
    required this.toMemberId,
    required this.status,
    required this.createdAt,
    this.rejectionCount = 0,
    this.resolvedAt,
  });

  final String id;
  final String tripId;
  final String fromLeaderId;
  final String toMemberId;
  final String status;
  final int rejectionCount;
  final DateTime createdAt;
  final DateTime? resolvedAt;
}

/// `trips/{tripId}/soloNotices`。未成年者的單獨行動需要正副隊長其中一位同意。
class SoloNotice {
  const SoloNotice({
    required this.id,
    required this.tripId,
    required this.memberId,
    required this.expectedBackAt,
    required this.isMinor,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String tripId;
  final String memberId;
  final DateTime expectedBackAt;
  final bool isMinor;
  final String status;
  final DateTime createdAt;
}

/// 同伴最後已知位置。只存一個點，不存地圖圖磚。
class LocationSnapshot {
  const LocationSnapshot({
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.sentAt,
    this.photoUrl,
  });

  final String userId;
  final double latitude;
  final double longitude;
  final DateTime sentAt;
  final String? photoUrl;
}

/// `invites/{code}`。建立後 1 小時到期。同一碼在到期前可以給多個人使用。
/// 產生新碼不會改寫其他碼的 [expiresAt]。
class InviteRecord {
  const InviteRecord({
    required this.code,
    required this.tripId,
    required this.createdBy,
    this.issuerRole = MemberRole.captain,
    this.tripTitle = '',
    this.active = true,
    required this.createdAt,
    required this.expiresAt,
  });

  final String code;
  final String tripId;
  final String createdBy;

  /// 產生這個碼當時的角色，寫進 `creatorRole`。之後升職或降職不會改這欄。
  final MemberRole issuerRole;
  final String tripTitle;
  final bool active;
  final DateTime createdAt;
  final DateTime expiresAt;
}

enum SyncOpType {
  upsertTrip,
  upsertMember,
  upsertRequest,
  upsertInvite,
  upsertItinerary,
  upsertRevision,
  upsertLocation,
}

class SyncOp {
  const SyncOp({required this.type, required this.tripId, this.entityId});

  final SyncOpType type;
  final String tripId;
  final String? entityId;

  bool sameAs(SyncOp other) =>
      type == other.type &&
      tripId == other.tripId &&
      entityId == other.entityId;
}

class TripException implements Exception {
  TripException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TripAccessDenied extends TripException {
  TripAccessDenied() : super(AppStrings.notMember);
}

class InviteNotFoundException extends TripException {
  InviteNotFoundException() : super(AppStrings.inviteNotFound);
}

class InviteExpiredException extends TripException {
  InviteExpiredException() : super(AppStrings.inviteExpired);
}

class InviteClosedException extends TripException {
  InviteClosedException() : super(AppStrings.inviteClosedByPublicInvite);
}

class AlreadyMemberException extends TripException {
  AlreadyMemberException() : super(AppStrings.alreadyMember);
}

class ValidationException extends TripException {
  ValidationException(super.message);
}

class RoleChangeException extends TripException {
  RoleChangeException(super.message);
}
