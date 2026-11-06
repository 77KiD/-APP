import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';

abstract class TripRemote {
  Future<DateTime> serverNow();

  /// 寫入 `clockProbes/{uid}.t` 後讀回，並用 [deviceNow] 算出時間差。
  Future<ServerClockReading> readServerClock(
    Future<DateTime> Function() deviceNow,
  );

  /// 等已經交給遠端的寫入送完。沒有離線佇列的實作直接返回。
  /// 本機時鐘樣本要等它完成才更新。客戶端不寫 `syncAnchors`。
  Future<void> flushPendingWrites();

  Future<void> upsertTrip(Trip trip);

  Future<Trip?> fetchTrip(String id);

  /// 只接受伺服器的結果，不退回裝置快取。需要確認旅程現況時用。
  Future<Trip?> fetchTripFromServer(String id);

  Future<List<Trip>> fetchTripsForUser(String userId);

  Future<void> upsertMember(TripMember member);

  Future<List<TripMember>> fetchMembers(String tripId);

  Future<void> upsertRequest(ModificationRequest request);

  /// 核准 [request]：旅程的預計回程時間與申請狀態一起寫入，全部成功或全部不留下。
  /// 伺服器上這筆申請已經被決定時丟出 [RequestHandledException]，伺服器不變。
  Future<void> approveRequest(ModificationRequest request);

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

  /// 分享專用：只回傳本次逐碼向遠端確認的結果，不沿用歷史確認。
  Future<({List<InviteRecord> invites, bool failed})> revalidateInvites(
    String tripId,
  );

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
