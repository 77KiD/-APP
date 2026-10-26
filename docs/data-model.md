# 資料模型

這份文件是集合路徑與欄位名稱的**唯一依據**。Flutter 客戶端（目錄 `app/`，另一個 PR）與 Cloud Functions 都照這裡寫，不要自創同義欄位。詞彙用 [GLOSSARY.md](../GLOSSARY.md)。決策見 ADR 0004、0005、0007、0008。

命名：欄位與集合用 camelCase。Google 地點 ID 依照詞彙表寫成 `place_id`。時間用 Firestore timestamp。沒有值的選填欄位寫 `null`，不要省略欄位。

Firestore 地區是 **asia-east1**（台灣）。地區在建立資料庫時指定，之後不能改：

```bash
firebase firestore:databases:create "(default)" --location=asia-east1
```

`.firebaserc` 的 `replace-with-firebase-project-id` 是占位，不要提交真實金鑰、`google-services.json` 或服務帳戶 JSON。

## 年齡

生日只存在 `users/{uid}.birthdate`，不複製進旅程。型別是 timestamp，必須是使用者選的日曆日的 **UTC 午夜**（`hours/minutes/seconds/nanos` 都是 0）。例如 2013-10-26 存 `Date.UTC(2013, 9, 26)`，不要把當地午夜轉成 timestamp，否則日期會偏移。

週年計算（規則與 `functions/src/age.ts` 同一套）：

- 滿 N 歲的瞬間是出生 UTC 日曆日加上 N 年的 UTC 午夜。
- 出生是 2 月 29 日，而目標年不是閏年時，週年改為該年 **3 月 1 日** UTC 午夜。
- `request.time >= 週年` 才算已滿。

| 判斷 | 規則 | 誰看得到 |
|---|---|---|
| 未滿 13 歲 | 不能建立 `users/{uid}`。沒有這個文件就不能建立旅程、讀邀請、加入成員 | 只有本人能讀 `birthdate` |
| 未成年 | 未滿 18 歲（ADR 0007，刻意不依各州規定） | 旅程成員只看 `members/{uid}.isMinor`，看不到生日 |

`birthdate` 建立後不能改。帳號刪除留給後續的 Cloud Function（ADR 0008），客戶端不能刪 `users/{uid}`。

Firebase Auth 帳號本身不帶生日，所以未滿 13 歲的人仍可能先建出 Auth 使用者。**註冊完成**的定義是成功寫入 `users/{uid}`。規則拒絕時，客戶端要登出並刪除剛建立的 Auth 使用者。權限錯誤表示未滿 13 歲、生日不是 UTC 午夜，或生日在未來。

## 路徑一覽

```
users/{uid}
  birthdate, displayName, photoUrl, createdAt, updatedAt
  syncAnchors/{deviceId}
    phoneWallClockAtSync, elapsedRealtimeAtSyncMs, updatedAt
  tripRefs/{tripId}
    tripId, role, tripTitle, updatedAt

invites/{code}
  tripId, tripTitle, createdBy, active, expiresAt, createdAt

trips/{tripId}
  schemaVersion, title, leaderId, status, startDate, endDate, timeZone,
  expectedReturnAt, generalTransport, returnTransport, returnFlight,
  startedAt, endedAt, endReason, invitesOpen, invitesResetAt, createdAt, updatedAt
  members/{uid}
    role, isMinor, displayName, photoUrl, inviteCode, joinedAt
  requests/{requestId}
    type, status, proposerId, payload, createdAt, expiresAt, decidedBy, decidedAt
  itinerary/{dayId}
    date, stops, backupStops, clientSavedAt, updatedBy, updatedAt
  itineraryHistory/{historyId}
    dayId, snapshot, clientSavedAt, updatedBy, recordedBy, outcome, createdAt
  places/{placeId}
    place_id, name, proposedBy, latitude, longitude, coordinatesCachedAt,
    replacesPlaceId, kind, createdAt, updatedAt
    votes/{uid}
      value, updatedAt
  locations/{uid}
    latitude, longitude, sentAt, receivedAt, photoUrl
  handover/{handoverId}          # 欄位見下方，寫入在 #14
  soloNotices/{noticeId}         # 欄位見下方，寫入在 #14
```

`trips` 不能 list。首頁讀 `users/{uid}/tripRefs`。邀請不能 list，只能用邀請碼 `get`。

## users/{uid}

| 欄位 | 型別 | 說明 |
|---|---|---|
| `birthdate` | timestamp | UTC 午夜。建立時須已滿 13 歲。之後不可改 |
| `displayName` | string | 1–40 字 |
| `photoUrl` | string \| null | 1–500 字，或 null |
| `createdAt` | timestamp | `FieldValue.serverTimestamp()` |
| `updatedAt` | timestamp | 同上，每次更新都寫 |

只有本人能讀寫。

### syncAnchors/{deviceId}

每次連線（佇列裡的離線寫入送出之後）寫一筆，供離線校正。`deviceId` 符合 `^[A-Za-z0-9_-]{1,64}$`。

| 欄位 | 型別 | 說明 |
|---|---|---|
| `phoneWallClockAtSync` | timestamp | 送出當下的手機牆鐘，與 `request.time` 差距須在 800 天內 |
| `elapsedRealtimeAtSyncMs` | int | Android `SystemClock.elapsedRealtime()`，0 到 100 年的毫秒 |
| `updatedAt` | timestamp | 伺服器時間。寫入後要讀回這個值，不要用送出前猜的時間 |

時鐘差（毫秒）= `updatedAt - phoneWallClockAtSync`。不要另存一個客戶端自填的 offset。

### tripRefs/{tripId}

使用者的旅程索引。文件 ID 等於 `tripId`。

| 欄位 | 型別 | 說明 |
|---|---|---|
| `tripId` | string | 等於文件 ID |
| `role` | string | 必須等於該成員文件上的 `role` |
| `tripTitle` | string | 列表用的標題快照，1–60 字 |
| `updatedAt` | timestamp | 伺服器時間 |

## invites/{code}

邀請碼 8–12 個英數（`[A-Za-z0-9]`）。任何**已註冊**使用者知道碼就能 `get`，但這份文件沒有行程內容，只有標題快照。

同一趟可以同時有多個有效碼。新碼**不會**使其他碼失效。同一個還有效的碼，在 1 小時內可以給多個人加入。

效期只跟伺服器的 `request.time` 比，不看手機時鐘。

| 欄位 | 型別 | 說明 |
|---|---|---|
| `tripId` | string | 目標旅程 |
| `tripTitle` | string | 建立當下的 `trips.title` |
| `createdBy` | string | 建立者 uid。`invitesOpen` 為 true 時可以是任何成員；關掉之後只能是隊長或副隊長 |
| `active` | bool | 建立時必須 true。隊長或副隊長可改成 false（撤銷）。不能改回 true，也不能改其他欄位 |
| `expiresAt` | timestamp | 必填，不能是 null。建立時必須落在 `request.time + 1 小時` 往前 5 分鐘到 `request.time + 1 小時`（含）之間，用來吸收客戶端對時誤差，同時禁止把效期拉過 1 小時 |
| `createdAt` | timestamp | 必須等於這次寫入的 `request.time` |

加入時四個條件都要成立：

- `active == true`
- `request.time < expiresAt`
- `request.time < createdAt + 1 小時`（就算 `expiresAt` 寫得比較晚，效期仍被建立時間卡住）
- 旅程的 `invitesResetAt` 是 null，或 `createdAt >= invitesResetAt`。更早的碼立刻不能加入，包含隊長、副隊長自己發的

誰能建立：

- `trips.invitesOpen == true`（建立旅程時的預設）：該趟的任何成員。
- `invitesOpen == false`：只有隊長或副隊長。
- 還不是成員的人不能建立。

關掉邀請是單獨的一筆旅程更新：`invitesOpen` 從 true 改成 false，而且同一筆把 `invitesResetAt` 設成這次的 `request.time`。這一筆使**當時所有還在效期內的碼**失效。之後隊長或副隊長發的新碼照常可用，直到各自的 1 小時。再把 `invitesOpen` 改回 true 時不能動 `invitesResetAt`，所以關掉之前的碼不會復活。若要再清掉關掉之後發出的碼，就再關一次，會寫入新的 `invitesResetAt`。一般成員不能改這兩個欄位。隊長或副隊長也可以把某個碼的 `active` 改成 false，那只撤銷那一個碼。

## trips/{tripId}

`schemaVersion` 目前固定 `1`。

| 欄位 | 型別 | 誰能直接改 |
|---|---|---|
| `title` | string | 1–60 字。任何成員 |
| `leaderId` | string | 建立時等於建立者。之後不可改（交接在 #14，走 Admin SDK） |
| `status` | `"planning"` \| `"active"` \| `"ended"` | 見下方 |
| `startDate` | string | `YYYY-MM-DD`，旅程當地日曆。任何成員。須 `<= endDate` |
| `endDate` | string | 結束日期，格式同上 |
| `timeZone` | string | IANA，例如 `Asia/Taipei`。沒填預計回程時間時，用它算結束日 23:59 |
| `expectedReturnAt` | timestamp \| null | **預計回程時間**。null 表示改走結束日 23:59。改成比 `request.time` 早會被拒絕。隊長或副隊長可直接改；一般成員只能送修改申請 |
| `generalTransport` | string \| null | **一般交通**（測試計畫裡的旅途中交通）。最多 200 字。權限同預計回程時間 |
| `returnTransport` | string \| null | **回程交通**的計畫（不是走散時的即時路線查詢，那個不落庫）。權限同上 |
| `returnFlight` | map \| null | **回程機票**。`{ summary: string, flightNumber: string \| null }`。`summary` 1–120 字，`flightNumber` 最多 20 字。旅程開始前隊長或副隊長可改；`startedAt` 有值之後所有客戶端寫入都必須保持原值。之後修改要全員同意，由 #14 的 Cloud Function 以 Admin SDK 寫入 |
| `startedAt` | timestamp \| null | 隊長把 `planning` 轉成 `active` 時寫伺服器時間。目前只有隊長能開始 |
| `endedAt` | timestamp \| null | 整團結束時間 |
| `endReason` | string \| null | 未結束時必須是 null。客戶端整團結束只能寫 `leader_manual`。排程寫 `expected_return` 或 `end_date` |
| `invitesOpen` | bool | 建立時必須 true。true 時任何成員可發邀請碼；false 時只有隊長或副隊長。只有隊長或副隊長能改，而且這次寫入不能順便改其他旅程欄位 |
| `invitesResetAt` | timestamp \| null | 建立時必須 null。關掉邀請的那一筆把它設成 `request.time`。加入時，`createdAt` 早於這個時間的碼一律拒絕。打開邀請時這個欄位必須維持原值 |
| `createdAt` / `updatedAt` | timestamp | 伺服器時間。`createdAt` 不變 |

`status`：

- 建立時是 `planning`。
- 隊長開始：`planning` → `active`，並寫 `startedAt`。這次寫入不能順便改交通或預計回程時間。
- 隊長或副隊長整團結束：`status = ended`、`endReason = leader_manual`、`endedAt` 為伺服器時間。一般成員按結束是個人結束（#14），這份規則不提供整團 `ended`。
- 結束後客戶端不能再改旅程本體。行程與景點仍可讀，位置不可讀。

建立順序：

1. 寫 `users/{uid}`（已滿 13 歲）。
2. 寫 `trips/{tripId}`（`leaderId` 是自己，`invitesOpen` 為 true，`invitesResetAt` 為 null）。此時建立者已能 `get` 旅程，因為 `leaderId` 相符。
3. 寫 `members/{uid}`，`role = leader`，`inviteCode = null`，`isMinor` 依生日。
4. 寫 `invites/{code}` 與 `users/{uid}/tripRefs/{tripId}`。

子集合的讀寫要求成員文件已存在，不能只靠 `leaderId`。

## members/{uid}

文件 ID 是使用者 uid。

| 欄位 | 型別 | 說明 |
|---|---|---|
| `role` | `"leader"` \| `"deputy"` \| `"member"` | 隊長、副隊長、一般成員 |
| `isMinor` | bool | 未滿 18 歲。必須等於帳號生日的計算結果。加入時寫入；本人生日跨過 18 歲後更新自己的成員文件 |
| `displayName` | string | 1–40 字。給其他成員看，避免去讀帳號文件 |
| `photoUrl` | string \| null | 同上 |
| `inviteCode` | string \| null | 隊長是 null。一般成員是用來加入的邀請碼 |
| `joinedAt` | timestamp | 伺服器時間 |

一般成員加入：`role` 只能是 `member`，邀請碼必須通過上面的伺服器時間檢查（含 `invitesResetAt`），`isMinor` 必須算對。不能自封隊長或副隊長。同一個有效碼可以重複使用。

隊長可把其他成員的 `role` 改成 `deputy` 或 `member`，不能改成 `leader`，也不能改對方的 `isMinor`。人數與副隊長是否必填（2–4 人不設、8 人以上必設）在 #14 才強制。

成員文件不能由客戶端刪除。退出與解散在 #14。

## requests/{requestId}

修改申請。一般成員改預計回程時間、一般交通、回程交通、回程機票時建立一筆，**不要**在同一筆未獲同意的寫入裡改 `trips` 那些欄位。隊長或副隊長同意時，用**同一個 batch** 做兩件事：把申請標成 `approved`，並寫入旅程欄位。batch 任一步被拒，兩步都不會留下（過去的預計回程時間因此不會出現「已同意但沒寫入」或相反）。

| 欄位 | 型別 | 說明 |
|---|---|---|
| `type` | string | `expected_return_at`、`general_transport`、`return_transport`、`return_flight` |
| `status` | string | 建立時 `pending`。隊長或副隊長改成 `approved` 或 `rejected`。客戶端不能寫 `expired` |
| `proposerId` | string | 建立者 uid |
| `payload` | map | 見下表。只含一個鍵 |
| `createdAt` | timestamp | 伺服器時間 |
| `expiresAt` | timestamp \| null | null 表示不過期（5–7 人且沒有副隊長的例外，過期工作在 #14）。有值則須落在現在起 31 分鐘內（30 分鐘加上餘裕） |
| `decidedBy` | string \| null | 同意或拒絕的隊長或副隊長 |
| `decidedAt` | timestamp \| null | 伺服器時間 |

`payload`：

| `type` | `payload` |
|---|---|
| `expected_return_at` | `{ expectedReturnAt: timestamp ≥ request.time 或 null }` |
| `general_transport` | `{ generalTransport: string \| null }` |
| `return_transport` | `{ returnTransport: string \| null }` |
| `return_flight` | `{ returnFlight: 與旅程欄位相同的 map 或 null }` |

## itinerary/{dayId} 與修改紀錄

`dayId` 是旅程時區的 `YYYY-MM-DD`，且 `date` 欄位必須相同。一天的衝突單位是這整份文件。

| 欄位 | 型別 | 說明 |
|---|---|---|
| `date` | string | 等於 `dayId` |
| `stops` | list | 當天行程，**最多 5 筆** |
| `backupStops` | list | 備選清單，最多 30 筆 |
| `clientSavedAt` | timestamp | 校正後的手機儲存時間。見離線同步。不可晚於伺服器現在 5 分鐘，也不可早於 400 天 |
| `updatedBy` | string | 這次寫入的 uid |
| `updatedAt` | timestamp | 伺服器收到的時間。排序不看這個欄位 |

`stops` 與 `backupStops` 的每個元素（規則無法逐筆檢查，客戶端必須照這個形狀）：

| 欄位 | 型別 | 說明 |
|---|---|---|
| `place_id` | string | Google Place ID，可長期保存 |
| `name` | string | 景點名稱 |
| `order` | int | 由 0 起 |
| `startAt` / `endAt` | timestamp \| null | 排定時間 |
| `latitude` / `longitude` | number \| null | 座標。超過 30 天必須改回 null |
| `coordinatesCachedAt` | timestamp \| null | 座標寫入的時間。兩個座標都是 null 時，這個也是 null |

覆蓋規則：更新時新的 `clientSavedAt` 必須 **大於或等於** 文件上的值。較舊的寫入被拒絕。相等時後送到伺服器的那次留下（重送同一筆因此可以成功）。被蓋過或被拒絕的內容寫入 `itineraryHistory`，客戶端在同一個 batch 裡寫上一版；若自己的寫入被拒，改寫一筆 `outcome = "lost"`。

### itineraryHistory/{historyId}

只能新增，不能改、不能刪（刪帳號時由 Admin SDK 處理）。旅程結束後仍可補寫，避免離線佇列裡的舊版消失。

| 欄位 | 型別 | 說明 |
|---|---|---|
| `dayId` | string | `YYYY-MM-DD` |
| `snapshot` | map | 被蓋過或沒被採用的那一版（至少含當時的 `stops`、`backupStops`、`clientSavedAt`、`updatedBy`） |
| `clientSavedAt` | timestamp | 那一版的校正儲存時間 |
| `updatedBy` | string | 做出那一版的 uid |
| `recordedBy` | string | 把紀錄寫進來的 uid，必須是現在的使用者 |
| `outcome` | `"superseded"` \| `"lost"` | `superseded`：較新的版本已寫上行程，這裡是上一版。`lost`：這次較舊，沒有蓋過行程 |
| `createdAt` | timestamp | 伺服器時間 |

## places/{placeId} 與 votes/{uid}

投票細節與排除門檻在 #4、#5。這裡只定欄位與「只有成員能讀寫」。

| 欄位 | 型別 | 說明 |
|---|---|---|
| `place_id` | string | Google Place ID |
| `name` | string | 1–120 字 |
| `proposedBy` | string | 建立者 uid，之後不變 |
| `latitude` / `longitude` | number \| null | 範圍內的座標。要嘛兩個都有，要嘛都是 null |
| `coordinatesCachedAt` | timestamp \| null | 有座標時必填，且距現在不超過 30 天、不晚於 5 分鐘 |
| `replacesPlaceId` | string \| null | 替代景點指向原景點文件 ID。`kind = alternative` 時必填 |
| `kind` | `"proposal"` \| `"alternative"` | 提議景點或替代景點 |
| `createdAt` / `updatedAt` | timestamp | 伺服器時間 |

`votes/{uid}` 的文件 ID 是投票者。`value` 只能是 `1`（想去）、`0`（沒意見）、`-1`（不想去）。改票用更新，不刪文件。不能寫別人的票。

景點文件不提供客戶端刪除（系統不自動刪景點）。

## locations/{uid}

發送定位。一位成員一份文件，再次發送直接覆蓋。

| 欄位 | 型別 | 說明 |
|---|---|---|
| `latitude` / `longitude` | number | 當下快照 |
| `sentAt` | timestamp | 按下「發送定位」的時間。可離線排隊；與伺服器時間差距須在過去 7 天到未來 2 分鐘內。畫面上的「N 分鐘前」用這個欄位 |
| `receivedAt` | timestamp | 伺服器收到的時間。聚合標記的頭像順序用這個欄位（#9），不用手機上的 `sentAt` |
| `photoUrl` | string \| null | 頭像 |

只有本人能寫或刪自己的文件。其他成員在旅程 `status != ended` 時可讀。結束後讀寫都拒絕（就算文件還在）。結束時 Cloud Function 會刪掉這些文件。

## handover 與 soloNotices

成員現在可以讀，不能寫。#14 才開放寫入。建議形狀先固定：

`handover/{handoverId}`：`fromLeaderId`、`toMemberId`、`status`（`pending` \| `accepted` \| `rejected` \| `assigned`）、`rejectionCount`、`createdAt`、`resolvedAt`。

`soloNotices/{noticeId}`：`memberId`、`expectedBackAt`、`isMinor`、`status`（`announced` \| `pending` \| `approved` \| `rejected`）、`createdAt`。

## 離線同步

Flutter 啟動 Firestore 時明示打開持久化（Android 預設雖已開啟，仍要寫出來）：

```dart
FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
```

可以留在手機上的是行程：景點名稱、順序、時間、`place_id`、未滿 30 天的座標，以及同伴最後已知位置。路線線條、交通時間、底圖不進持久化，也不要為了離線去呼叫 Directions 再把結果存下來。離線時把還在期限內的景點連成直線，並顯示「連線後更新路線」。

衝突以**校正後的 `clientSavedAt`** 最新的一筆為準，不看伺服器收到的先後。校正公式與 `functions/src/clockCorrection.ts` 相同（下面的數字就是單元測試的輸入）：

```
offsetMs = anchor.updatedAtMs - anchor.phoneWallClockAtSyncMs

若 elapsedRealtimeNowMs >= anchor.elapsedRealtimeAtSyncMs:
  clientSavedAtMs = anchor.updatedAtMs + (elapsedRealtimeNowMs - anchor.elapsedRealtimeAtSyncMs)
否則（重開機，elapsedRealtime 歸零）:
  clientSavedAtMs = phoneWallClockNowMs + offsetMs
```

範例（與 `functions/test/clockCorrection.test.ts` 相同）：同步時伺服器 `updatedAtMs = 1000000000000`，手機牆鐘快 1 小時（`phoneWallClockAtSyncMs = 1000003600000`），`elapsedRealtimeAtSyncMs = 50000`。`offsetMs = -3600000`。

- 沒重開機，elapsed 變成 80000：`clientSavedAtMs = 1000000030000`。牆鐘即使亂調也不參與。
- 重開機後 elapsed 是 1000、牆鐘是 `1000000100000`：`clientSavedAtMs = 999996500000`。

連線順序：先讓 Firestore 把離線佇列送完，再寫新的 `syncAnchors`。佇列裡的 `clientSavedAt` 用的是送出前那次同步的錨點，不因新錨點被改算。離線期間若重開機，才改走牆鐘加最後一次 offset；若那時有人調過手機時間，順序可能失準（ADR 0004 已接受）。

成員可以在 5 分鐘的未來上限內填 `clientSavedAt`。這是骨架的信任邊界，#12 可以再收緊。

## 旅程自動結束

`endExpiredTrips` 每 5 分鐘跑一次（Cloud Functions 地區 `asia-east1`）。它每次讀**現在文件上的** `expectedReturnAt`，所以把預計回程時間改晚，下一次執行就會用新時間，不用另排一個工作。

| 條件 | `endReason` |
|---|---|
| `expectedReturnAt` 有值，且現在 ≥ 該時間 | `expected_return` |
| `expectedReturnAt` 是 null，且現在 ≥ `endDate` 當天 23:59:00（`timeZone`） | `end_date` |
| `status` 已是 `ended` | 不動作 |

`planning` 與 `active` 都會被結束，避免沒按開始的旅程留下位置。時區或日期無法解釋的旅程會略過並記 log，不會猜一個時間。

23:59:00 的 UTC 瞬間（單元測試鎖定）：

| 時區 | `endDate` | UTC |
|---|---|---|
| `Asia/Taipei` | 2026-10-26 | 2026-10-26T15:59:00.000Z |
| `Asia/Tokyo` | 2026-10-26 | 2026-10-26T14:59:00.000Z |
| `America/New_York`（EDT） | 2026-10-26 | 2026-10-27T03:59:00.000Z |

有預計回程時間時，**不再**看結束日 23:59。即使 23:59 已過，只要預計回程時間還在未來，旅程就繼續。

`status` 變成 `ended` 時，`clearLocationsWhenTripEnds` 刪除 `locations` 全部文件。排程自己也會刪一次。規則在 `ended` 之後拒絕讀寫位置，所以刪除前的空窗也不會被成員讀到。

客戶端不能把 `endReason` 寫成 `expected_return` 或 `end_date`。那兩個值只有上述函式用 Admin SDK 寫入。

## 本票不做、名稱先定住的行為

- 8 人以上沒有副隊長不能開始、2–4 人不能有副隊長、修改申請 30 分鐘過期與推播、回程機票全員同意後寫回、交接抽籤、單獨行動、個人結束：#14。申請文件已可建立。
- 投票計分、排除、替代景點流程：#4、#5。`places` 與 `votes` 已可讀寫。
- 排路線演算法：#6。結果寫回 `itinerary/{dayId}.stops`，排不進的放 `backupStops`。
- 帳號刪除（個資、位置、生日、修改紀錄裡的個人內容、回憶錄）：後續 Cloud Function。其他人的行程留下，顯示名稱改為「已刪除的成員」。
- 行程 `stops` 裡單筆座標的 30 天上限，規則無法逐筆檢查。景點文件 `places` 已強制。客戶端讀行程時要自己清掉過期座標；之後可以加排程掃描。

## 測試

```bash
npm ci --prefix functions && npm test --prefix functions
npm ci --prefix rules-tests
npx --prefix rules-tests firebase emulators:exec --project demo-app --only firestore "npm --prefix rules-tests test"
```

規則測試需要 JDK 21。模擬器專案 ID 用 `demo-app`，不需要真實 Firebase 專案。
