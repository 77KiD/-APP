# 團體自由行（Flutter）

Android 用戶端。設定 Firebase、資料路徑與後端待辦寫在倉庫根目錄的 [README](../README.md)。

```bash
flutter pub get
flutter analyze
flutter test
```

沒有 `--dart-define=FIREBASE_*` 時走本機帳號與本機旅程，不會連上 Firebase。

## 邀請碼的發布與同步

跨手機邀請需要兩端都使用同一 Firebase 專案的連線版。加入時會向伺服器讀取
`invites/{code}`，網路讀取失敗與文件不存在會分開處理。

發碼會重新檢查連線，並在寫入後讀回伺服器確認；確認前不顯示可分享的碼。
離線仍可建立旅程，但會顯示「尚未同步」，沒有複製按鈕。恢復連線後，可以按
旅程頁右上角的同步按鈕或產生新碼。尚未發布的舊碼會在首次上傳時取得有效時間，
已發布碼的重試不會延長效期。舊版快取缺少確認狀態時，也必須讀回伺服器才可分享。

邀請碼維持 8–12 個英數，輸入接受全形英數、大小寫與貼上時的空白；停用鍵盤
自動修正，其他標點不會被靜默移除。

## Windows 開發環境

將 Flutter SDK 的 `bin` 目錄加入 PATH，並重新開啟終端機。尚未設定 PATH 時，
可在 PowerShell 使用 SDK 完整路徑執行（路徑請依實際安裝位置調整）：

```powershell
& 'C:\Users\s1593\develop\flutter\bin\flutter.bat' doctor -v
```

Android 開發還需要 Android SDK Command-line Tools。安裝後執行
`flutter doctor --android-licenses`，閱讀並確認 SDK 授權，再用 `flutter doctor -v`
確認工具鏈。能執行分析與單元測試，不代表 Android 打包環境已完整。

## 截圖基準測試

`.github/workflows/flutter.yml` 目前以 Ubuntu、Flutter 3.47.8 執行測試與產生
`test/goldens/` 基準圖。Windows 或不同 Flutter 版本可能在文字和圖示邊緣產生
光柵化差異，造成逐像素比對失敗；請查看 `test/failures/` 的差異圖，並以 CI
結果確認是否有真正的畫面回歸。

不要僅因本機跨平台比對失敗就覆寫基準圖。需要更新時，從 GitHub Actions 手動
執行 Flutter workflow，下載 `regenerate-goldens` job 的 `goldens` artifact，
審查圖片後再提交。`test/failures/` 是本機診斷產物，不提交至版本控制。
