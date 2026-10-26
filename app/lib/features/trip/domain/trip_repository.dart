import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';

abstract class TripRemote {
  Future<DateTime> serverNow();

  Future<void> upsertTrip(Trip trip);

  Future<Trip?> fetchTrip(String id);

  Future<List<Trip>> fetchTripsForUser(String userId);

  Future<void> upsertMember(TripMember member);

  Future<List<TripMember>> fetchMembers(String tripId);

  Future<void> upsertRequest(ModificationRequest request);

  Future<List<ModificationRequest>> fetchRequests(String tripId);

  Future<void> upsertInvite(InviteRecord invite);

  Future<InviteRecord?> fetchInvite(String code);

  Future<List<InviteRecord>> fetchInvites(String tripId);

  Future<Trip> join({required String code, required TripMember member});

  Future<void> upsertItineraryDay(ItineraryDay day);

  Future<ItineraryDay?> fetchItineraryDay(String tripId, String date);

  Future<List<ItineraryDay>> fetchItinerary(String tripId);

  Future<void> upsertRevision(ItineraryRevision revision);

  Future<void> upsertLocation(String tripId, LocationSnapshot snapshot);

  Future<List<LocationSnapshot>> fetchLocations(String tripId);
}

abstract class TripRepository {
  Future<Trip> createTrip(NewTripForm form);

  Future<Trip> getTrip(String tripId);

  Future<List<Trip>> listMyTrips();

  Future<List<TripMember>> listMembers(String tripId);

  Future<Trip> updateExpectedReturnTime({
    required String tripId,
    required DateTime? proposed,
  });

  Future<ModificationRequest> submitExpectedReturnRequest({
    required String tripId,
    required DateTime proposed,
  });

  Future<Trip> approveRequest({
    required String tripId,
    required String requestId,
  });

  Future<ModificationRequest> rejectRequest({
    required String tripId,
    required String requestId,
  });

  Future<List<ModificationRequest>> listRequests(String tripId);

  Future<void> assignViceCaptain({
    required String tripId,
    required String userId,
  });

  Future<Trip> joinWithInviteCode(String code);

  Future<InviteRecord> issueInviteCode(String tripId);

  Future<Trip> setPublicInvite({required String tripId, required bool enabled});

  Future<List<InviteRecord>> listInvites(String tripId);

  Future<void> saveItineraryDay(ItineraryDay day);

  Future<ItineraryDay?> readItineraryDay(String tripId, String date);

  Future<List<ItineraryRevision>> readItineraryRevisions(
    String tripId,
    String date,
  );

  Future<void> saveLastKnownLocation(String tripId, LocationSnapshot snapshot);

  Future<List<LocationSnapshot>> readLastKnownLocations(String tripId);

  Future<void> sync();
}
