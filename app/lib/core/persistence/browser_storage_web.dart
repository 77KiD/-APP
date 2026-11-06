import 'package:web/web.dart' as web;

String? browserStorageRead(String key) => web.window.localStorage.getItem(key);

void browserStorageWrite(String key, String value) =>
    web.window.localStorage.setItem(key, value);

/// 網頁的網址，用來讀邀請連結 `/j/<邀請碼>`。
Uri? browserLocation() => Uri.tryParse(web.window.location.href);
