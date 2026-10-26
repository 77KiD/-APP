# 團體自由行

Android 用戶端在 `app/`（Flutter，feature-first）。規格以 [issue #1](https://github.com/77KiD/-APP/issues/1)、[GLOSSARY.md](GLOSSARY.md) 與 [docs/adr](docs/adr) 為準。這一版對應 [issue #3](https://github.com/77KiD/-APP/issues/3) 的前端骨架：登入、註冊（未滿 13 歲不能建立帳號）、建立旅程、邀請與加入、角色（隊長／副隊長／一般成員）、離線資料層、同意後才開 Analytics／Crashlytics、要求定位權限前的說明畫面。

介面文字是繁體中文。Firestore 安全規則與 Cloud Functions 由後端另外做，這個版本庫沒有規則檔。

## 本機執行

需要 Flutter 3.47.8（Dart 3.13.7）。

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter run
```

沒有帶 Firebase 編譯參數時，App 用本機帳號與本機旅程檔，不會連上 Firebase。畫面會顯示尚未設定 Firebase。

## 接上 Firebase

金鑰不要進版本庫。`app/android/app/google-services.json` 已在 `.gitignore`。範例是 `app/android/app/google-services.json.example`（內容是 `REPLACE_ME`，套件名稱 `com.example.group_trip`）。

1. 在 Firebase 建立 Android App，套件名稱先用 `com.example.group_trip`（之後若改 `applicationId`，`google-services.json` 要一起換）。
2. 把下載的 `google-services.json` 放到 `app/android/app/google-services.json`。有這個檔時，Gradle 才套用 `com.google.gms.google-services`。
3. 用編譯參數把同一組公開設定傳進 Dart。這些值會出現在用戶端，仍然不要寫進原始碼：

```bash
cd app
flutter run \
  --dart-define=FIREBASE_API_KEY=你的apiKey \
  --dart-define=FIREBASE_APP_ID=你的appId \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=你的senderId \
  --dart-define=FIREBASE_PROJECT_ID=你的projectId \
  --dart-define=FIREBASE_STORAGE_BUCKET=你的storageBucket
```

四個必填（`FIREBASE_API_KEY`、`FIREBASE_APP_ID`、`FIREBASE_MESSAGING_SENDER_ID`、`FIREBASE_PROJECT_ID`）都有值時才初始化 Firebase Auth 與 Firestore。初始化時會把 Firestore 離線持久化打開（`persistenceEnabled: true`，快取大小不設上限）。`AndroidManifest` 預設關閉 Analytics 與 Crashlytics 收集；使用者在同意畫面點頭之後，App 才各自打開。

這一版沒有在 manifest 宣告 `ACCESS_FINE_LOCATION` 或背景定位。定位說明畫面只記錄「我知道了」，不會向系統要權限。真正要求權限要等之後的「發送定位」。

## 資料路徑

旅程是根（ADR 0005）。時間以 UTC ISO-8601 字串儲存，日期是 `YYYY-MM-DD`。

| 路徑 | 內容 |
| --- | --- |
| `users/{uid}` | 顯示名稱、生日、頭像網址、分析與當機報告同意。沒有密碼。 |
| `trips/{tripId}` | 標題、隊長、起迄日、IANA `timeZone`、選填 `expectedReturnAt`、建立當下的邀請碼、`publicInvite`（公開邀請，預設 true）、狀態、`memberIds`、建立與更新時間。 |
| `trips/{tripId}/members/{uid}` | 顯示名稱、`role`（`captain`／`viceCaptain`／`member`）、`isMinor`、加入時間。沒有生日。 |
| `trips/{tripId}/requests/{id}` | 預計回程時間的修改申請。`expiresAt` 可為 null。 |
| `trips/{tripId}/itineraryDays/{YYYY-MM-DD}` | 當天景點：名稱、順序、時間、`placeId`、座標與座標快取時間。 |
| `trips/{tripId}/itineraryHistory/{id}` | 被覆蓋的行程版本。 |
| `trips/{tripId}/locations/{uid}` | 位置快照形狀。這一版沒有發送定位。 |
| `trips/{tripId}/handover/{id}`、`trips/{tripId}/soloNotices/{id}` | 交接與單獨行動的形狀。流程不在 #3。 |
| `inviteCodes/{CODE}` | `tripId`、`createdBy`、`createdAt`、`expiresAt`（建立後 1 小時）。非成員用邀請碼加入時先查這層。同一個碼在到期前可以給多個人用。新碼不會改寫其他碼。 |
| `_meta/clock` | 登入使用者寫入 `FieldValue.serverTimestamp()`，給 ADR 0004 的校正時鐘。不含個資。 |

角色在畫面上是隊長、副隊長、一般成員。一般成員改預計回程時間會送修改申請；隊長與副隊長直接寫入。不能改成比現在早。副隊長最多一位，而且只有成員至少 5 人、由隊長指定。8 人以上沒有副隊長時，介面會說明還不能開始，這一版沒有「開始旅程」按鈕。

公開邀請預設開啟，任何成員都可以產生邀請碼。隊長關掉之後，只有隊長和副隊長可以產生；一般成員的按鈕會停用，並說明原因。畫面上的剩餘時間依這台手機估算，只供參考。加入時是否過期以伺服器時間與 `expiresAt` 為準。

離線時先寫本機 JSON，恢復連線再送出。行程以校正後的 `updatedAt` 後寫入勝出，落敗的版本進 `itineraryHistory`。離線快取只留行程名稱、順序、時間、`place_id` 與座標；座標以 UTC 日曆日計算，滿 30 日刪除，名稱與 `place_id` 保留。不快取 Google 路線、交通時間或地圖圖磚。

## 測試

```bash
cd app
flutter test
```

CI（`.github/workflows/flutter.yml`）在 Flutter 3.47.8 上跑 `flutter analyze` 與 `flutter test`。接受標準用假的遠端與本機檔，不連 Firebase 模擬器。未滿 13 歲不能註冊，以及斷網仍可建立旅程，都有測試。

## 留給後端

- Firebase 專案、Auth、Firestore，以及真正的 `google-services.json`（不要提交）。
- 安全規則：非成員不能讀旅程；生日只在 `users`；成員文件沒有生日；`inviteCodes/{code}` 讓已登入者讀得到該碼以便加入，但讀不到行程；列出某旅程的邀請碼只限成員。加入時必須用伺服器時間拒絕 `request.time >= expiresAt`。寫入時 `expiresAt` 不得晚於 `createdAt` 加 1 小時。`publicInvite == false` 時，只有隊長和副隊長可以新增邀請碼。`_meta/clock` 允許已登入使用者寫入伺服器時間戳、不能寫個資。用戶端檢查不是安全邊界。
- Cloud Functions：修改申請到期、旅程在預計回程時間（或沒填時的結束日 23:59，旅程時區）結束並清位置、刪除帳號、8 人以上沒有副隊長不能開始。
- 模擬器加規則的 CI。用戶端測試用假實作，對應 issue #1 允許的做法。
- FCM、Maps 金鑰、發送定位。這一版不收集 FCM 權杖，也沒有背景定位。

Gradle 在有 `google-services.json` 時才套用外掛。這個環境沒有跑過 Android Gradle 建置。
