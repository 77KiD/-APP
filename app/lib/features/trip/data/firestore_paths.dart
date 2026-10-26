import 'package:group_trip/data/firestore_schema.dart';

/// 旅程是根。名稱定義在 [FirestoreSchema]，這裡保留既有的常數名稱。
abstract final class FirestorePaths {
  static const trips = FirestoreSchema.trips;
  static const members = FirestoreSchema.members;
  static const requests = FirestoreSchema.requests;
  static const itinerary = FirestoreSchema.itinerary;
  static const itineraryHistory = FirestoreSchema.itineraryHistory;
  static const handover = FirestoreSchema.handover;
  static const soloNotices = FirestoreSchema.soloNotices;
  static const locations = FirestoreSchema.locations;
  static const places = FirestoreSchema.places;
  static const inviteCodes = FirestoreSchema.invites;
  static const users = FirestoreSchema.users;
  static const syncAnchors = FirestoreSchema.syncAnchors;
  static const tripRefs = FirestoreSchema.tripRefs;
  static const clockProbes = FirestoreSchema.clockProbes;

  static const all = [
    trips,
    members,
    requests,
    itinerary,
    itineraryHistory,
    handover,
    soloNotices,
    locations,
    places,
    inviteCodes,
    users,
    syncAnchors,
    tripRefs,
    clockProbes,
  ];
}
