import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:group_trip/features/trip/data/firestore_paths.dart';
import 'package:group_trip/features/trip/domain/trip_codec.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
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
    final ref = _firestore
        .collection(FirestorePaths.meta)
        .doc(FirestorePaths.clock);
    await ref.set({'now': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    final snap = await ref.get();
    final value = snap.data()?['now'];
    if (value is Timestamp) return value.toDate().toUtc();
    return DateTime.now().toUtc();
  }

  @override
  Future<void> upsertTrip(Trip trip) async {
    await _trips.doc(trip.id).set(TripCodec.tripToMap(trip), SetOptions(merge: true));
  }

  @override
  Future<Trip?> fetchTrip(String id) async {
    final snap = await _trips.doc(id).get();
    final data = snap.data();
    if (data == null) return null;
    return TripCodec.tripFromMap(data, id: id);
  }

  @override
  Future<List<Trip>> fetchTripsForUser(String userId) async {
    final query = await _trips.where('memberIds', arrayContains: userId).get();
    return [
      for (final doc in query.docs) TripCodec.tripFromMap(doc.data(), id: doc.id),
    ];
  }

  @override
  Future<void> upsertMember(TripMember member) async {
    await _trips
        .doc(member.tripId)
        .collection(FirestorePaths.members)
        .doc(member.userId)
        .set(TripCodec.memberToMap(member), SetOptions(merge: true));
    await _trips.doc(member.tripId).set({
      'memberIds': FieldValue.arrayUnion([member.userId]),
    }, SetOptions(merge: true));
  }

  @override
  Future<List<TripMember>> fetchMembers(String tripId) async {
    final query = await _trips.doc(tripId).collection(FirestorePaths.members).get();
    return [for (final doc in query.docs) TripCodec.memberFromMap(doc.data())];
  }

  @override
  Future<void> upsertRequest(ModificationRequest request) async {
    await _trips
        .doc(request.tripId)
        .collection(FirestorePaths.requests)
        .doc(request.id)
        .set(TripCodec.requestToMap(request), SetOptions(merge: true));
  }

  @override
  Future<List<ModificationRequest>> fetchRequests(String tripId) async {
    final query = await _trips
        .doc(tripId)
        .collection(FirestorePaths.requests)
        .get();
    return [for (final doc in query.docs) TripCodec.requestFromMap(doc.data())];
  }

  @override
  Future<void> upsertInvite({
    required String code,
    required String tripId,
    required DateTime createdAt,
  }) async {
    await _invites.doc(code).set(
      TripCodec.inviteToMap(tripId: tripId, createdAt: createdAt),
    );
  }

  @override
  Future<Trip> join({required String code, required TripMember member}) async {
    final invite = await _invites.doc(code.trim().toUpperCase()).get();
    final tripId = invite.data()?['tripId'];
    if (!invite.exists || tripId is! String) throw InviteNotFoundException();
    final existing = await _trips
        .doc(tripId)
        .collection(FirestorePaths.members)
        .doc(member.userId)
        .get();
    if (existing.exists) throw AlreadyMemberException();
    final saved = TripMember(
      tripId: tripId,
      userId: member.userId,
      displayName: member.displayName,
      photoUrl: member.photoUrl,
      role: MemberRole.member,
      isMinor: member.isMinor,
      joinedAt: member.joinedAt,
    );
    await upsertMember(saved);
    final snap = await _trips.doc(tripId).get();
    final data = snap.data();
    if (data == null) {
      throw TripException('已加入旅程，但還讀不到旅程資料。請確認 Firestore 規則允許成員讀取。');
    }
    return TripCodec.tripFromMap(data, id: tripId);
  }

  @override
  Future<void> upsertItineraryDay(ItineraryDay day) async {
    await _trips
        .doc(day.tripId)
        .collection(FirestorePaths.itineraryDays)
        .doc(day.date)
        .set(TripCodec.dayToMap(day), SetOptions(merge: true));
  }

  @override
  Future<ItineraryDay?> fetchItineraryDay(String tripId, String date) async {
    final snap = await _trips
        .doc(tripId)
        .collection(FirestorePaths.itineraryDays)
        .doc(date)
        .get();
    final data = snap.data();
    if (data == null) return null;
    return TripCodec.dayFromMap(data);
  }

  @override
  Future<List<ItineraryDay>> fetchItinerary(String tripId) async {
    final query = await _trips
        .doc(tripId)
        .collection(FirestorePaths.itineraryDays)
        .get();
    return [for (final doc in query.docs) TripCodec.dayFromMap(doc.data())];
  }

  @override
  Future<void> upsertRevision(ItineraryRevision revision) async {
    await _trips
        .doc(revision.tripId)
        .collection(FirestorePaths.itineraryHistory)
        .doc(revision.id)
        .set(TripCodec.revisionToMap(revision));
  }

  @override
  Future<void> upsertLocation(String tripId, LocationSnapshot snapshot) async {
    await _trips
        .doc(tripId)
        .collection(FirestorePaths.locations)
        .doc(snapshot.userId)
        .set(TripCodec.locationToMap(snapshot), SetOptions(merge: true));
  }

  @override
  Future<List<LocationSnapshot>> fetchLocations(String tripId) async {
    final query = await _trips
        .doc(tripId)
        .collection(FirestorePaths.locations)
        .get();
    return [for (final doc in query.docs) TripCodec.locationFromMap(doc.data())];
  }

  /// 路徑保留給後端規則與後續功能，這一版的畫面還不會寫入。
  DocumentReference<Map<String, dynamic>> handoverRef(String tripId, String id) {
    return _trips.doc(tripId).collection(FirestorePaths.handover).doc(id);
  }

  DocumentReference<Map<String, dynamic>> soloNoticeRef(String tripId, String id) {
    return _trips.doc(tripId).collection(FirestorePaths.soloNotices).doc(id);
  }
}
