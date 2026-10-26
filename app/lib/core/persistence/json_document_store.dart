import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 本機 JSON 文件。讀寫都走同一條佇列，避免兩次離線寫入互相蓋掉。
abstract class JsonDocumentStore {
  Future<void> _chain = Future<void>.value();

  Future<Map<String, dynamic>> read();

  Future<void> write(Map<String, dynamic> data);

  Future<T> view<T>(T Function(Map<String, dynamic> data) body) {
    final completer = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        completer.complete(body(_clone(await read())));
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<void> transaction(void Function(Map<String, dynamic> draft) body) {
    final completer = Completer<void>();
    _chain = _chain.then((_) async {
      try {
        final draft = _clone(await read());
        body(draft);
        await write(draft);
        completer.complete();
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Map<String, dynamic> _clone(Map<String, dynamic> data) {
    return jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  }
}

class MemoryDocumentStore extends JsonDocumentStore {
  Map<String, dynamic> _data = {};

  @override
  Future<Map<String, dynamic>> read() async =>
      jsonDecode(jsonEncode(_data)) as Map<String, dynamic>;

  @override
  Future<void> write(Map<String, dynamic> data) async {
    _data = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
  }
}

class FileDocumentStore extends JsonDocumentStore {
  FileDocumentStore(this.file);

  final File file;

  @override
  Future<Map<String, dynamic>> read() async {
    if (!await file.exists()) return {};
    final text = await file.readAsString();
    if (text.trim().isEmpty) return {};
    final decoded = jsonDecode(text);
    if (decoded is! Map) return {};
    return Map<String, dynamic>.from(decoded);
  }

  @override
  Future<void> write(Map<String, dynamic> data) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data));
  }
}
