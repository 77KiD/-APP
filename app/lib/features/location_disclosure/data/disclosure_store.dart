import 'package:group_trip/core/persistence/json_document_store.dart';

class DisclosureStore {
  DisclosureStore(this._store);

  final JsonDocumentStore _store;

  Future<bool> isAcknowledged(String userId) {
    return _store.view((data) {
      final acked = data['acked'];
      if (acked is! Map) return false;
      return acked[userId] == true;
    });
  }

  Future<void> acknowledge(String userId) {
    return _store.transaction((draft) {
      final acked = draft['acked'];
      final next = acked is Map
          ? Map<String, dynamic>.from(acked)
          : <String, dynamic>{};
      next[userId] = true;
      draft['acked'] = next;
    });
  }
}
