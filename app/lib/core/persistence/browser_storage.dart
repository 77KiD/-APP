// 網頁版用瀏覽器的 localStorage；其他平台沒有瀏覽器，呼叫會丟錯。
export 'browser_storage_stub.dart'
    if (dart.library.js_interop) 'browser_storage_web.dart';
