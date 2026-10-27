import 'dart:async';

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
///
/// 若 [staleSnapshotHold] 內沒有較新的快照、也沒有 `serverRestored`，就改顯示
/// 伺服器目前這筆（被先壓住的那版）。
class ItineraryDayViewState {
  const ItineraryDayViewState({
    required this.localUserId,
    this.displayed,
    this.serverRestored = false,
    this.pendingOwnWrite,
    this.heldSnapshot,
    this.heldAt,
  });

  /// 較舊快照先不換畫面，等較新版本或 `serverRestored` 的時間。
  static const staleSnapshotHold = Duration(seconds: 10);

  final String localUserId;
  final ItineraryDay? displayed;
  final bool serverRestored;
  final ItineraryDay? pendingOwnWrite;

  /// 先不顯示的伺服器版本。時間到了還是沒有較新版本，就改顯示這一筆。
  final ItineraryDaySnapshot? heldSnapshot;

  /// 開始壓住較舊快照的時間。之後又來的較舊快照不會把這段等待重算。
  final DateTime? heldAt;

  /// 本機編輯尚未被伺服器確認。即使它的 `clientSavedAt` 比較舊，畫面也改顯示這一筆。
  ItineraryDayViewState showPendingOwnWrite(ItineraryDay day) {
    return ItineraryDayViewState(
      localUserId: localUserId,
      displayed: day,
      serverRestored: false,
      pendingOwnWrite: day,
    );
  }

  ItineraryDayViewState applySnapshot(
    ItineraryDaySnapshot snapshot, {
    DateTime? now,
  }) {
    final clock = (now ?? DateTime.now()).toUtc();
    return expireHold(clock)._apply(snapshot, clock);
  }

  /// 等待已滿 [staleSnapshotHold] 時，改顯示被壓住的伺服器版本。
  ItineraryDayViewState expireHold(DateTime now) {
    final started = heldAt;
    final held = heldSnapshot;
    if (started == null || held == null) return this;
    if (now.toUtc().difference(started.toUtc()) < staleSnapshotHold) {
      return this;
    }
    return ItineraryDayViewState(
      localUserId: localUserId,
      displayed: held.day,
      serverRestored: held.serverRestored,
      pendingOwnWrite: pendingOwnWrite,
    );
  }

  ItineraryDayViewState _apply(ItineraryDaySnapshot snapshot, DateTime now) {
    if (_isOwnPending(snapshot.day)) {
      return ItineraryDayViewState(
        localUserId: localUserId,
        displayed: snapshot.day,
        serverRestored: snapshot.serverRestored,
      );
    }
    final current = displayed?.clientSavedAt;
    if (current != null && snapshot.day.clientSavedAt.isBefore(current)) {
      if (pendingOwnWrite != null) return this;
      return ItineraryDayViewState(
        localUserId: localUserId,
        displayed: displayed,
        serverRestored: serverRestored,
        pendingOwnWrite: pendingOwnWrite,
        heldSnapshot: snapshot,
        heldAt: heldAt ?? now,
      );
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
    return TripCodec.spotsKey(incoming.spots) ==
        TripCodec.spotsKey(pending.spots);
  }
}

/// Firestore listener 套用快照，並在 [ItineraryDayViewState.staleSnapshotHold] 後放棄等待。
class ItineraryDayListener {
  ItineraryDayListener({
    required this.state,
    DateTime Function()? now,
    this.onChanged,
  }) : _now = now ?? DateTime.now;

  ItineraryDayViewState state;
  final DateTime Function() _now;
  final void Function(ItineraryDayViewState state)? onChanged;
  Timer? _timer;

  void onSnapshot(ItineraryDaySnapshot snapshot) {
    _publish(state.applySnapshot(snapshot, now: _now()));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  void _publish(ItineraryDayViewState next) {
    state = next;
    _timer?.cancel();
    _timer = null;
    final heldAt = next.heldAt;
    if (heldAt != null) {
      final elapsed = _now().toUtc().difference(heldAt.toUtc());
      final remaining = ItineraryDayViewState.staleSnapshotHold - elapsed;
      _timer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
        _timer = null;
        _publish(state.expireHold(_now()));
      });
    }
    onChanged?.call(state);
  }
}
