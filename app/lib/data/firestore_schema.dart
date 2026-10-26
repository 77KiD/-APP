/// 集合與欄位名稱，對齊 `docs/data-model.md`。
/// 後端會拿這份檔案對文件。其他地方不要再寫這些字串。
abstract final class FirestoreSchema {
  static const schemaVersionValue = 1;
  static const maxTitleLength = 60;
  static const maxDisplayNameLength = 40;
  static const inviteCodeMinLength = 8;
  static const inviteCodeMaxLength = 12;

  static const users = 'users';
  static const syncAnchors = 'syncAnchors';
  static const tripRefs = 'tripRefs';

  /// 每位使用者只寫自己的文件，用來讀回伺服器時間。不是 `_meta/clock`。
  static const clockProbes = 'clockProbes';

  static const invites = 'invites';
  static const trips = 'trips';
  static const members = 'members';
  static const requests = 'requests';
  static const itinerary = 'itinerary';
  static const itineraryHistory = 'itineraryHistory';
  static const places = 'places';
  static const votes = 'votes';
  static const locations = 'locations';
  static const handover = 'handover';
  static const soloNotices = 'soloNotices';

  static const probeTime = 't';

  static const birthdate = 'birthdate';
  static const displayName = 'displayName';
  static const photoUrl = 'photoUrl';
  static const createdAt = 'createdAt';
  static const updatedAt = 'updatedAt';

  static const phoneWallClockAtSync = 'phoneWallClockAtSync';
  static const elapsedRealtimeAtSyncMs = 'elapsedRealtimeAtSyncMs';

  static const tripId = 'tripId';
  static const role = 'role';
  static const tripTitle = 'tripTitle';
  static const roleLeader = 'leader';
  static const roleDeputy = 'deputy';
  static const roleMember = 'member';

  static const createdBy = 'createdBy';
  static const creatorRole = 'creatorRole';
  static const active = 'active';
  static const expiresAt = 'expiresAt';

  static const schemaVersion = 'schemaVersion';
  static const title = 'title';
  static const leaderId = 'leaderId';
  static const status = 'status';
  static const statusPlanning = 'planning';
  static const statusActive = 'active';
  static const statusEnded = 'ended';
  static const startDate = 'startDate';
  static const endDate = 'endDate';
  static const timeZone = 'timeZone';
  static const expectedReturnAt = 'expectedReturnAt';
  static const generalTransport = 'generalTransport';
  static const returnTransport = 'returnTransport';
  static const returnFlight = 'returnFlight';
  static const flightSummary = 'summary';
  static const flightNumber = 'flightNumber';
  static const startedAt = 'startedAt';
  static const endedAt = 'endedAt';
  static const endReason = 'endReason';
  static const endReasonLeaderManual = 'leader_manual';
  static const invitesOpen = 'invitesOpen';
  static const invitesResetAt = 'invitesResetAt';

  static const tripFields = {
    schemaVersion,
    title,
    leaderId,
    status,
    startDate,
    endDate,
    timeZone,
    expectedReturnAt,
    generalTransport,
    returnTransport,
    returnFlight,
    startedAt,
    endedAt,
    endReason,
    invitesOpen,
    invitesResetAt,
    createdAt,
    updatedAt,
  };

  static const isMinor = 'isMinor';
  static const inviteCode = 'inviteCode';
  static const joinedAt = 'joinedAt';

  static const memberFields = {
    role,
    isMinor,
    displayName,
    photoUrl,
    inviteCode,
    joinedAt,
  };

  static const inviteFields = {
    tripId,
    tripTitle,
    createdBy,
    creatorRole,
    active,
    expiresAt,
    createdAt,
  };

  static const userFields = {
    birthdate,
    displayName,
    photoUrl,
    createdAt,
    updatedAt,
  };

  static const type = 'type';
  static const proposerId = 'proposerId';
  static const payload = 'payload';
  static const decidedBy = 'decidedBy';
  static const decidedAt = 'decidedAt';
  static const requestTypeExpectedReturn = 'expected_return_at';
  static const requestTypeGeneralTransport = 'general_transport';
  static const requestTypeReturnTransport = 'return_transport';
  static const requestTypeReturnFlight = 'return_flight';

  static const date = 'date';
  static const stops = 'stops';
  static const backupStops = 'backupStops';
  static const clientSavedAt = 'clientSavedAt';
  static const updatedBy = 'updatedBy';
  static const placeId = 'place_id';
  static const name = 'name';
  static const order = 'order';
  static const startAt = 'startAt';
  static const endAt = 'endAt';
  static const latitude = 'latitude';
  static const longitude = 'longitude';
  static const coordinatesCachedAt = 'coordinatesCachedAt';

  static const dayId = 'dayId';
  static const snapshot = 'snapshot';
  static const recordedBy = 'recordedBy';
  static const outcome = 'outcome';
  static const outcomeSuperseded = 'superseded';
  static const outcomeLost = 'lost';

  static const proposedBy = 'proposedBy';
  static const replacesPlaceId = 'replacesPlaceId';
  static const kind = 'kind';
  static const kindProposal = 'proposal';
  static const kindAlternative = 'alternative';
  static const voteValue = 'value';

  static const sentAt = 'sentAt';
  static const receivedAt = 'receivedAt';

  static const fromLeaderId = 'fromLeaderId';
  static const toMemberId = 'toMemberId';
  static const rejectionCount = 'rejectionCount';
  static const resolvedAt = 'resolvedAt';
  static const handoverStatusPending = 'pending';
  static const handoverStatusAccepted = 'accepted';
  static const handoverStatusRejected = 'rejected';
  static const handoverStatusAssigned = 'assigned';

  static const memberId = 'memberId';
  static const expectedBackAt = 'expectedBackAt';
  static const noticeStatusAnnounced = 'announced';
  static const noticeStatusPending = 'pending';
  static const noticeStatusApproved = 'approved';
  static const noticeStatusRejected = 'rejected';
}

/// 只留在手機 JSON。不要寫進 Firestore 文件。
abstract final class LocalOnlyFields {
  static const documentId = 'id';
  static const memberIds = 'memberIds';
  static const userId = 'userId';
  static const requesterName = 'requesterName';
  static const savedAt = 'savedAt';
  static const authorId = 'authorId';
  static const legacyPlaceId = 'placeId';
  static const legacyStartTime = 'startTime';
  static const legacyEndTime = 'endTime';
  static const legacySpots = 'spots';
  static const analyticsConsent = 'analyticsConsent';
  static const crashlyticsConsent = 'crashlyticsConsent';
  static const consentDecided = 'consentDecided';
  static const email = 'email';
  static const birthday = 'birthday';
  static const issuerRole = 'issuerRole';
  static const requesterId = 'requesterId';
  static const resolvedBy = 'resolvedBy';
  static const proposedExpectedReturnAt = 'proposedExpectedReturnAt';
  static const legacyRoleCaptain = 'captain';
  static const legacyRoleDeputy = 'viceCaptain';
  static const sessionUserId = 'sessionUserId';
  static const passwordSalt = 'passwordSalt';
  static const passwordHash = 'passwordHash';
  static const queue = 'queue';
  static const timeSample = 'timeSample';
  static const acked = 'acked';
  static const serverNow = 'serverNow';
  static const deviceNow = 'deviceNow';
  static const elapsedMs = 'elapsedMs';
  static const encodedPolyline = 'encodedPolyline';
  static const polyline = 'polyline';
  static const durationSeconds = 'durationSeconds';
  static const travelDuration = 'travelDuration';
  static const route = 'route';
  static const mapTile = 'mapTile';
}
