String? browserStorageRead(String key) =>
    throw UnsupportedError('browser storage is only available on the web');

void browserStorageWrite(String key, String value) =>
    throw UnsupportedError('browser storage is only available on the web');

/// 網頁的網址；非網頁平台沒有。
Uri? browserLocation() => null;
