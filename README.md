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

旅程是根（ADR 0005）。寫進 Firestore 的時間是 timestamp，本機 JSON 用 UTC ISO-8601。日期是 `YYYY-MM-DD`。欄位名稱集中在 `app/lib/data/firestore_schema.dart`，對齊 `docs/data-model.md`。

| 路徑 | 內容 |
| --- | --- |
| `users/{uid}` | `birthdate`（UTC 午夜 timestamp）、`displayName`、`photoUrl`、`createdAt`、`updatedAt`。沒有密碼，也沒有分析同意。同意只留在這台手機。 |
| `users/{uid}/tripRefs/{tripId}` | 首頁用的旅程索引。`trips` 不能列出。 |
| `users/{uid}/syncAnchors/{deviceId}` | 離線校正錨點。佇列送完才寫。 |
| `clockProbes/{uid}` | 唯一欄位 `t`。用戶端寫 `FieldValue.serverTimestamp()`，讀回來和手機牆鐘相減得到時間差。每人只能讀寫自己的文件。 |
| `trips/{tripId}` | `schemaVersion`、`title`、`leaderId`、起迄日、`timeZone`、`expectedReturnAt`、交通欄位、`invitesOpen`、`invitesResetAt`、狀態與建立／更新時間。沒有 `captainId`、`memberIds`、`inviteCode`。 |
| `trips/{tripId}/members/{uid}` | `role`（`leader`／`deputy`／`member`）、`isMinor`、`displayName`、`photoUrl`、`inviteCode`、`joinedAt`。沒有生日。 |
| `trips/{tripId}/requests/{id}` | 修改申請。預計回程時間的 `type` 是 `expected_return_at`。 |
| `trips/{tripId}/itinerary/{YYYY-MM-DD}` | `stops`、`backupStops`、`clientSavedAt`、`updatedBy`、`updatedAt`。景點用 `place_id`。 |
| `trips/{tripId}/itineraryHistory/{id}` | 被覆蓋或沒被採用的行程版本。 |
| `trips/{tripId}/locations/{uid}` | 位置快照形狀。這一版沒有發送定位。 |
| `trips/{tripId}/handover/{id}`、`trips/{tripId}/soloNotices/{id}` | 交接與單獨行動的形狀。流程不在 #3。 |
| `invites/{CODE}` | 8–12 個英數。`tripId`、`tripTitle`、`createdBy`、`creatorRole`（產生當下的 `leader`／`deputy`／`member`）、`active`、`createdAt`、`expiresAt`。同一個碼在到期前可以給多個人用。新碼不會改寫其他碼。 |

角色在畫面上是隊長、副隊長、一般成員。寫進文件的字串是 `leader`、`deputy`、`member`。一般成員改預計回程時間會送修改申請；隊長與副隊長直接寫入。不能改成比現在早。副隊長最多一位，而且只有成員至少 5 人、由隊長指定。8 人以上沒有副隊長時，介面會說明還不能開始，這一版沒有「開始旅程」按鈕。

公開邀請（`invitesOpen`）預設開啟，任何成員都可以產生邀請碼。隊長或副隊長關掉時，同一筆寫入把 `invitesResetAt` 設成伺服器時間。一般成員在這個時間之前產生的邀請碼立刻不能加入，再打開公開邀請也不會清掉 `invitesResetAt`，那些碼不會恢復。隊長和副隊長產生的碼仍用到各自的 `expiresAt`。產生新碼不會改寫其他碼。一般成員的按鈕會停用，並說明原因。畫面上的剩餘時間依這台手機估算，只供參考。加入時是否過期以伺服器時間為準。

離線時先寫本機 JSON，恢復連線再送出。行程以校正後的 `updatedAt` 後寫入勝出，落敗的版本進 `itineraryHistory`。離線快取只留行程名稱、順序、時間、`place_id` 與座標；座標以 UTC 日曆日計算，滿 30 日刪除，名稱與 `place_id` 保留。不快取 Google 路線、交通時間或地圖圖磚。

## 測試

```bash
cd app
flutter test
```

CI（`.github/workflows/flutter.yml`）在 Flutter 3.47.8 上跑 `flutter analyze` 與 `flutter test`，另外用 Firestore 模擬器跑 `integration/rules-contract`，確認現在的寫入形狀能通過後端規則。未滿 13 歲不能註冊，以及斷網仍可建立旅程，都有測試。

## 留給後端

- Firebase 專案、Auth、Firestore，以及真正的 `google-services.json`（不要提交）。
- 安全規則與 Cloud Functions 仍由後端維護。這個用戶端依 `docs/data-model.md` 寫入，不在這裡改規則。
- 伺服器時間走 `clockProbes/{uid}` 的 `t`，不再使用 `_meta/clock`。
- Cloud Functions：修改申請到期、旅程在預計回程時間（或沒填時的結束日 23:59，旅程時區）結束並清位置、刪除帳號、8 人以上沒有副隊長不能開始。
- FCM、Maps 金鑰、發送定位。這一版不收集 FCM 權杖，也沒有背景定位。

Gradle 在有 `google-services.json` 時才套用外掛。這個環境沒有跑過 Android Gradle 建置。
