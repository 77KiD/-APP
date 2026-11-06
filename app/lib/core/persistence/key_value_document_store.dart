import 'dart:convert';

import 'package:group_trip/core/persistence/json_document_store.dart';

/// 把整份 JSON 文件存成一個字串。網頁版沒有檔案系統，用瀏覽器的
/// localStorage（見 `browser_storage.dart`），ADR 0012。
class KeyValueDocumentStore extends JsonDocumentStore {
  KeyValueDocumentStore({
    required this.key,
    required this.readString,
    required this.writeString,
  });

  final String key;
  final String? Function(String key) readString;
  final void Function(String key, String value) writeString;

  @override
  Future<Map<String, dynamic>> read() async {
    final raw = readString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      // 壞掉的資料不擋開啟；之後的寫入會覆蓋。
      return {};
    }
  }

  @override
  Future<void> write(Map<String, dynamic> data) async {
    writeString(key, jsonEncode(data));
  }
}
