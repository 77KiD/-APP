import 'package:group_trip/data/firestore_schema.dart';
import 'package:group_trip/features/trip/domain/trip_codec.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';

/// Firestore `itinerary/{dayId}` 的一筆 listener 快照。
class ItineraryDaySnapshot {
  const ItineraryDaySnapshot({required this.day, this.serverRestored = false});

  final ItineraryDay day;

  /// 伺服器把較新的版本寫回來時為 true。較舊、即將被蓋回的那一筆不是這個標記。
  final bool serverRestored;

  static ItineraryDaySnapshot fromMap(Map<String, dynamic> map) {
    return ItineraryDaySnapshot(
      day: TripCodec.dayFromMap(map),
      serverRestored: map[FirestoreSchema.serverRestored] == true,
    );
  }
}

/// 行程一天的畫面狀態。
///
/// Listener 送來的快照若 [ItineraryDay.clientSavedAt] 比畫面上的舊，先不要換畫面。
/// 伺服器會很快把較新的版本寫回來，那一筆帶 [ItineraryDaySnapshot.serverRestored]。
/// 例外是這支手機自己還沒送完的寫入：那一筆即使比較舊也要顯示。
class ItineraryDayViewState {
  const ItineraryDayViewState({
    required this.localUserId,
    this.displayed,
    this.serverRestored = false,
    this.pendingOwnWrite,
  });

  final String localUserId;
  final ItineraryDay? displayed;
  final bool serverRestored;
  final ItineraryDay? pendingOwnWrite;

  /// 本機編輯尚未被伺服器確認。即使它的 `clientSavedAt` 比較舊，畫面也改顯示這一筆。
  ItineraryDayViewState showPendingOwnWrite(ItineraryDay day) {
    return ItineraryDayViewState(
      localUserId: localUserId,
      displayed: day,
      serverRestored: false,
      pendingOwnWrite: day,
    );
  }

  ItineraryDayViewState applySnapshot(ItineraryDaySnapshot snapshot) {
    if (_isOwnPending(snapshot.day)) {
      return ItineraryDayViewState(
        localUserId: localUserId,
        displayed: snapshot.day,
        serverRestored: snapshot.serverRestored,
        pendingOwnWrite: null,
      );
    }
    final current = displayed?.clientSavedAt;
    if (current != null && snapshot.day.clientSavedAt.isBefore(current)) {
      return this;
    }
    return ItineraryDayViewState(
      localUserId: localUserId,
      displayed: snapshot.day,
      serverRestored: snapshot.serverRestored,
      pendingOwnWrite: pendingOwnWrite,
    );
  }

  bool _isOwnPending(ItineraryDay incoming) {
    final pending = pendingOwnWrite;
    if (pending == null) return false;
    if (incoming.authorId != localUserId || pending.authorId != localUserId) {
      return false;
    }
    if (incoming.clientSavedAt.toUtc().millisecondsSinceEpoch !=
        pending.clientSavedAt.toUtc().millisecondsSinceEpoch) {
      return false;
    }
    return TripCodec.spotsKey(incoming.spots) == TripCodec.spotsKey(pending.spots);
  }
}
