import 'package:group_trip/core/persistence/json_document_store.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/data/firestore_schema.dart';
import 'package:group_trip/features/trip/domain/trip_codec.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';

class TripLocalStore {
  TripLocalStore(this._store);

  final JsonDocumentStore _store;

  Future<Trip?> readTrip(String id) {
    return _store.view((data) {
      final raw = _child(data, FirestoreSchema.trips)[id];
      if (raw is! Map) return null;
      return TripCodec.tripFromMap(Map<String, dynamic>.from(raw));
    });
  }

  Future<void> saveTrip(Trip trip) {
    return _store.transaction((draft) {
      final trips = _child(draft, FirestoreSchema.trips);
      trips[trip.id] = TripCodec.tripToLocalMap(trip);
      draft[FirestoreSchema.trips] = trips;
    });
  }

  Future<List<Trip>> readAllTrips() {
    return _store.view((data) {
      final trips = _child(data, FirestoreSchema.trips);
      return [
        for (final raw in trips.values)
          if (raw is Map) TripCodec.tripFromMap(Map<String, dynamic>.from(raw)),
      ];
    });
  }

  Future<bool> isMember(String tripId, String userId) async {
    final members = await readMembers(tripId);
    return members.any((member) => member.userId == userId);
  }

  Future<List<TripMember>> readMembers(String tripId) {
    return _store.view((data) {
      final raw = _child(data, FirestoreSchema.members)[tripId];
      if (raw is! Map) return [];
      return [
        for (final item in raw.values)
          if (item is Map)
            TripCodec.memberFromMap(Map<String, dynamic>.from(item)),
      ];
    });
  }

  Future<void> saveMember(TripMember member) {
    return _store.transaction((draft) {
      final root = _child(draft, FirestoreSchema.members);
      final current = root[member.tripId];
      final tripMembers = current is Map
          ? Map<String, dynamic>.from(current)
          : <String, dynamic>{};
      tripMembers[member.userId] = TripCodec.memberToLocalMap(member);
      root[member.tripId] = tripMembers;
      draft[FirestoreSchema.members] = root;
    });
  }

  Future<void> saveMembers(String tripId, List<TripMember> members) {
    return _store.transaction((draft) {
      final root = _child(draft, FirestoreSchema.members);
      root[tripId] = {
        for (final member in members)
          member.userId: TripCodec.memberToLocalMap(member),
      };
      draft[FirestoreSchema.members] = root;
    });
  }

  Future<List<ModificationRequest>> readRequests(String tripId) {
    return _store.view((data) {
      final raw = _child(data, FirestoreSchema.requests)[tripId];
      if (raw is! Map) return [];
      return [
        for (final item in raw.values)
          if (item is Map)
            TripCodec.requestFromMap(Map<String, dynamic>.from(item)),
      ];
    });
  }

  Future<void> saveRequest(ModificationRequest request) {
    return _store.transaction((draft) {
      final root = _child(draft, FirestoreSchema.requests);
      final current = root[request.tripId];
      final tripRequests = current is Map
          ? Map<String, dynamic>.from(current)
          : <String, dynamic>{};
      tripRequests[request.id] = TripCodec.requestToLocalMap(request);
      root[request.tripId] = tripRequests;
      draft[FirestoreSchema.requests] = root;
    });
  }

  Future<void> saveRequests(String tripId, List<ModificationRequest> requests) {
    return _store.transaction((draft) {
      final root = _child(draft, FirestoreSchema.requests);
      root[tripId] = {
        for (final request in requests)
          request.id: TripCodec.requestToLocalMap(request),
      };
      draft[FirestoreSchema.requests] = root;
    });
  }

  Future<void> saveInvite(InviteRecord invite) {
    final code = invite.code.trim().toUpperCase();
    return _store.transaction((draft) {
      final invites = _child(draft, FirestoreSchema.invites);
      invites[code] = TripCodec.inviteToMap(invite);
      draft[FirestoreSchema.invites] = invites;
    });
  }

  Future<InviteRecord?> readInvite(String code) {
    return _store.view((data) {
      final value = _child(
        data,
        FirestoreSchema.invites,
      )[code.trim().toUpperCase()];
      if (value is! Map) return null;
      return TripCodec.inviteFromMap(
        Map<String, dynamic>.from(value),
        code: code.trim().toUpperCase(),
      );
    });
  }

  Future<List<InviteRecord>> readInvites(String tripId) {
    return _store.view((data) {
      final records = <InviteRecord>[];
      for (final entry in _child(data, FirestoreSchema.invites).entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final record = TripCodec.inviteFromMap(
          Map<String, dynamic>.from(value),
          code: entry.key,
        );
        if (record.tripId == tripId) records.add(record);
      }
      return records;
    });
  }

  Future<void> saveItineraryDay(ItineraryDay day) {
    return _store.transaction((draft) {
      final root = _child(draft, FirestoreSchema.itinerary);
      final current = root[day.tripId];
      final days = current is Map
          ? Map<String, dynamic>.from(current)
          : <String, dynamic>{};
      days[day.date] = TripCodec.dayToMap(day);
      root[day.tripId] = days;
      draft[FirestoreSchema.itinerary] = root;
    });
  }

  Future<ItineraryDay?> readItineraryDay(String tripId, String date) {
    return _store.view((data) {
      final trip = _child(data, FirestoreSchema.itinerary)[tripId];
      if (trip is! Map) return null;
      final raw = trip[date];
      if (raw is! Map) return null;
      return TripCodec.dayFromMap(Map<String, dynamic>.from(raw));
    });
  }

  Future<List<ItineraryDay>> readItinerary(String tripId) {
    return _store.view((data) {
      final trip = _child(data, FirestoreSchema.itinerary)[tripId];
      if (trip is! Map) return [];
      return [
        for (final raw in trip.values)
          if (raw is Map) TripCodec.dayFromMap(Map<String, dynamic>.from(raw)),
      ];
    });
  }

  Future<void> saveRevision(ItineraryRevision revision) {
    return _store.transaction((draft) {
      final root = _child(draft, FirestoreSchema.itineraryHistory);
      final current = root[revision.tripId];
      final revisions = current is Map
          ? Map<String, dynamic>.from(current)
          : <String, dynamic>{};
      revisions[revision.id] = TripCodec.revisionToMap(revision);
      root[revision.tripId] = revisions;
      draft[FirestoreSchema.itineraryHistory] = root;
    });
  }

  Future<List<ItineraryRevision>> readRevisions(String tripId, String date) {
    return _store.view((data) {
      final trip = _child(data, FirestoreSchema.itineraryHistory)[tripId];
      if (trip is! Map) return [];
      return [
        for (final raw in trip.values)
          if (raw is Map)
            TripCodec.revisionFromMap(Map<String, dynamic>.from(raw)),
      ].where((revision) => revision.date == date).toList();
    });
  }

  Future<void> saveLocation(String tripId, LocationSnapshot snapshot) {
    return _store.transaction((draft) {
      final root = _child(draft, FirestoreSchema.locations);
      final current = root[tripId];
      final people = current is Map
          ? Map<String, dynamic>.from(current)
          : <String, dynamic>{};
      people[snapshot.userId] = TripCodec.locationToLocalMap(tripId, snapshot);
      root[tripId] = people;
      draft[FirestoreSchema.locations] = root;
    });
  }

  Future<List<LocationSnapshot>> readLocations(String tripId) {
    return _store.view((data) {
      final raw = _child(data, FirestoreSchema.locations)[tripId];
      if (raw is! Map) return [];
      return [
        for (final item in raw.values)
          if (item is Map)
            TripCodec.locationFromMap(Map<String, dynamic>.from(item)),
      ];
    });
  }

  Future<void> enqueue(SyncOp op) {
    return _store.transaction((draft) {
      final queue = _list(draft, LocalOnlyFields.queue);
      final exists = queue.any((item) {
        if (item is! Map) return false;
        return TripCodec.syncOpFromMap(Map<String, dynamic>.from(item))
            .sameAs(op);
      });
      if (!exists) queue.add(TripCodec.syncOpToMap(op));
      draft[LocalOnlyFields.queue] = queue;
    });
  }

  Future<List<SyncOp>> readQueue() {
    return _store.view((data) {
      return [
        for (final item in _list(data, LocalOnlyFields.queue))
          if (item is Map)
            TripCodec.syncOpFromMap(Map<String, dynamic>.from(item)),
      ];
    });
  }

  Future<void> removeOp(SyncOp op) {
    return _store.transaction((draft) {
      final queue = _list(draft, LocalOnlyFields.queue);
      queue.removeWhere((item) {
        if (item is! Map) return false;
        return TripCodec.syncOpFromMap(Map<String, dynamic>.from(item))
            .sameAs(op);
      });
      draft[LocalOnlyFields.queue] = queue;
    });
  }

  Future<TimeSample?> readTimeSample() {
    return _store.view(
      (data) => TimeSample.fromMap(data[LocalOnlyFields.timeSample]),
    );
  }

  Future<void> saveTimeSample(TimeSample sample) {
    return _store.transaction((draft) {
      draft[LocalOnlyFields.timeSample] = sample.toMap();
    });
  }

  Map<String, dynamic> _child(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<dynamic> _list(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is List) return List<dynamic>.from(value);
    return <dynamic>[];
  }
}
