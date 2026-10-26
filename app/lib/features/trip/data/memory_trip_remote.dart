import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/features/trip/domain/trip_repository.dart';

/// 兩台手機可以各有一個 [MemoryTripRemote]，共用這一份資料。
class MemoryTripDatabase {
  DateTime clock = DateTime.utc(2026, 10, 26);
  final trips = <String, Trip>{};
  final members = <String, Map<String, TripMember>>{};
  final requests = <String, Map<String, ModificationRequest>>{};
  final invites = <String, InviteRecord>{};
  final itinerary = <String, Map<String, ItineraryDay>>{};
  final revisions = <String, Map<String, ItineraryRevision>>{};
  final locations = <String, Map<String, LocationSnapshot>>{};
}

/// 測試用的遠端。預設會擋下非成員讀取，用來對齊「非成員無法讀取旅程」。
class MemoryTripRemote implements TripRemote {
  MemoryTripRemote({
    required this.database,
    required this.currentUserId,
    this.enforceMembership = true,
  });

  final MemoryTripDatabase database;
  final String Function() currentUserId;
  bool enforceMembership;

  @override
  Future<DateTime> serverNow() async => database.clock.toUtc();

  @override
  Future<void> upsertTrip(Trip trip) async {
    database.trips[trip.id] = trip;
  }

  @override
  Future<Trip?> fetchTrip(String id) async {
    final trip = database.trips[id];
    if (trip == null) return null;
    _ensureMember(id);
    return trip;
  }

  @override
  Future<List<Trip>> fetchTripsForUser(String userId) async {
    return [
      for (final trip in database.trips.values)
        if (trip.memberIds.contains(userId)) trip,
    ];
  }

  @override
  Future<void> upsertMember(TripMember member) async {
    final tripMembers = database.members.putIfAbsent(member.tripId, () => {});
    tripMembers[member.userId] = member;
    final trip = database.trips[member.tripId];
    if (trip != null && !trip.memberIds.contains(member.userId)) {
      database.trips[member.tripId] = trip.copy(
        memberIds: [...trip.memberIds, member.userId],
      );
    }
  }

  @override
  Future<List<TripMember>> fetchMembers(String tripId) async {
    _ensureMember(tripId);
    return [...?database.members[tripId]?.values];
  }

  @override
  Future<void> upsertRequest(ModificationRequest request) async {
    final tripRequests = database.requests.putIfAbsent(request.tripId, () => {});
    tripRequests[request.id] = request;
  }

  @override
  Future<List<ModificationRequest>> fetchRequests(String tripId) async {
    _ensureMember(tripId);
    return [...?database.requests[tripId]?.values];
  }

  @override
  Future<void> upsertInvite(InviteRecord invite) async {
    final code = invite.code.trim().toUpperCase();
    database.invites[code] = InviteRecord(
      code: code,
      tripId: invite.tripId,
      createdBy: invite.createdBy,
      issuerRole: invite.issuerRole,
      createdAt: invite.createdAt.toUtc(),
      expiresAt: invite.expiresAt.toUtc(),
    );
  }

  @override
  Future<InviteRecord?> fetchInvite(String code) async {
    return database.invites[code.trim().toUpperCase()];
  }

  @override
  Future<List<InviteRecord>> fetchInvites(String tripId) async {
    _ensureMember(tripId);
    return [
      for (final invite in database.invites.values)
        if (invite.tripId == tripId) invite,
    ];
  }

  @override
  Future<Trip> join({required String code, required TripMember member}) async {
    final invite = database.invites[code.trim().toUpperCase()];
    if (invite == null || !database.trips.containsKey(invite.tripId)) {
      throw InviteNotFoundException();
    }
    if (TripPolicy.isInviteExpired(invite.expiresAt, database.clock)) {
      throw InviteExpiredException();
    }
    final tripId = invite.tripId;
    final tripForInvite = database.trips[tripId]!;
    if (TripPolicy.memberInviteBlocked(
      publicInvite: tripForInvite.publicInvite,
      issuerRole: invite.issuerRole,
    )) {
      throw InviteClosedException();
    }
    final tripMembers = database.members.putIfAbsent(tripId, () => {});
    if (tripMembers.containsKey(member.userId)) throw AlreadyMemberException();
    final saved = TripMember(
      tripId: tripId,
      userId: member.userId,
      displayName: member.displayName,
      photoUrl: member.photoUrl,
      role: MemberRole.member,
      isMinor: member.isMinor,
      joinedAt: member.joinedAt,
    );
    tripMembers[saved.userId] = saved;
    final trip = database.trips[tripId]!;
    final updated = trip.copy(
      memberIds: [...trip.memberIds, saved.userId],
      updatedAt: member.joinedAt,
    );
    database.trips[tripId] = updated;
    return updated;
  }

  @override
  Future<void> upsertItineraryDay(ItineraryDay day) async {
    final days = database.itinerary.putIfAbsent(day.tripId, () => {});
    days[day.date] = day;
  }

  @override
  Future<ItineraryDay?> fetchItineraryDay(String tripId, String date) async {
    _ensureMember(tripId);
    return database.itinerary[tripId]?[date];
  }

  @override
  Future<List<ItineraryDay>> fetchItinerary(String tripId) async {
    _ensureMember(tripId);
    return [...?database.itinerary[tripId]?.values];
  }

  @override
  Future<void> upsertRevision(ItineraryRevision revision) async {
    final items = database.revisions.putIfAbsent(revision.tripId, () => {});
    items[revision.id] = revision;
  }

  @override
  Future<void> upsertLocation(String tripId, LocationSnapshot snapshot) async {
    final people = database.locations.putIfAbsent(tripId, () => {});
    people[snapshot.userId] = snapshot;
  }

  @override
  Future<List<LocationSnapshot>> fetchLocations(String tripId) async {
    _ensureMember(tripId);
    return [...?database.locations[tripId]?.values];
  }

  void _ensureMember(String tripId) {
    if (!enforceMembership) return;
    final tripMembers = database.members[tripId];
    if (tripMembers == null || !tripMembers.containsKey(currentUserId())) {
      throw TripAccessDenied();
    }
  }
}
