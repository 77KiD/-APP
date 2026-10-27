import 'package:group_trip/data/firestore_schema.dart';
import 'package:group_trip/features/trip/domain/trip_codec.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';

/// 行程一天的合併與 Firestore 部分更新。
///
/// 修改行程時預設不帶 `backupStops`。只有 [ItineraryDay.replaceBackupStops]
/// 為 true，或文件還不存在（建立時規則要求這個欄位）才寫備選清單。
abstract final class ItineraryDayWrite {
  static ItineraryDay merge({
    required ItineraryDay? existing,
    required ItineraryDay incoming,
  }) {
    final List<ItinerarySpot>? backups;
    if (existing == null) {
      backups = incoming.backupStops ?? const <ItinerarySpot>[];
    } else if (incoming.replaceBackupStops) {
      backups = incoming.backupStops ?? const <ItinerarySpot>[];
    } else {
      backups = existing.backupStops;
    }
    final spots = existing == null || !_sameSpots(existing.spots, incoming.spots)
        ? incoming.spots
        : existing.spots;
    return ItineraryDay(
      tripId: incoming.tripId,
      date: incoming.date,
      spots: spots,
      backupStops: backups,
      replaceBackupStops: false,
      updatedAt: incoming.updatedAt,
      authorId: incoming.authorId,
    );
  }

  /// 只含有變動的欄位。時間值是 UTC [DateTime]，寫入 Firestore 時再轉成 timestamp。
  /// `updatedAt` 有放進這份 map 時，呼叫端改寫成 `FieldValue.serverTimestamp()`。
  static Map<String, Object?> changedFields({
    required ItineraryDay? existing,
    required ItineraryDay incoming,
  }) {
    final merged = merge(existing: existing, incoming: incoming);
    final patch = <String, Object?>{};
    if (existing == null || existing.date != merged.date) {
      patch[FirestoreSchema.date] = merged.date;
    }
    if (existing == null || !_sameSpots(existing.spots, merged.spots)) {
      patch[FirestoreSchema.stops] = _encode(merged.spots);
    }
    if (existing == null || incoming.replaceBackupStops) {
      final next = merged.backupStops ?? const <ItinerarySpot>[];
      final unchanged = existing != null &&
          _sameSpots(existing.backupStops ?? const <ItinerarySpot>[], next);
      if (!unchanged) {
        patch[FirestoreSchema.backupStops] = _encode(next);
      }
    }
    if (existing == null || !_sameInstant(existing.updatedAt, merged.updatedAt)) {
      patch[FirestoreSchema.clientSavedAt] = merged.updatedAt.toUtc();
    }
    if (existing == null || existing.authorId != merged.authorId) {
      patch[FirestoreSchema.updatedBy] = merged.authorId;
    }
    if (patch.isNotEmpty) {
      patch[FirestoreSchema.updatedAt] = merged.updatedAt.toUtc();
    }
    return patch;
  }

  static List<Map<String, dynamic>> _encode(List<ItinerarySpot> spots) => [
    for (final spot in spots) TripCodec.spotToMap(spot),
  ];

  static bool _sameSpots(List<ItinerarySpot> left, List<ItinerarySpot> right) =>
      TripCodec.spotsKey(left) == TripCodec.spotsKey(right);

  static bool _sameInstant(DateTime left, DateTime right) =>
      left.toUtc().millisecondsSinceEpoch == right.toUtc().millisecondsSinceEpoch;
}
