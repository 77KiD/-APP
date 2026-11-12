# 0013 不升 Blaze 的架構
- 狀態：已接受（2026-11-12，提議 2026-11-11）｜關聯：0002、0004、0007、0008、0009 第 3 點、0010、0011、0012 第 5 點、#33、#31
## 背景
治齊決定現階段維持 Spark 免費方案，不升 Blaze（2026-11-10）。Spark 不能部署 Cloud Functions，也不能啟用帳單，所以：
- `functions/` 裡的 `endExpiredTrips`（排程自動結束旅程）與 `clearLocationsWhenTripEnds`（旅程結束時清除位置）目前沒有部署，也不會執行。
- Google Places 等要綁帳單的 Google 地圖平台服務不能用在 `peers-bea4b`。在同一個專案上開帳單會讓 Firebase 自動變成 Blaze。
- 推播（FCM 從伺服器發送）沒有地方執行。

本 ADR 決定在 Spark 上各項功能怎麼做，以及哪些等 Blaze 才做。
## 決策
1. **原則**：需要伺服器的邏輯，改成「由 Firestore 規則把關的客戶端寫入」。規則是唯一的權限邊界，客戶端寫入的每個欄位都要能用規則驗證。做不到的功能先放佔位，不用客戶端假裝做到。
2. **地點來源與 `place_id`**（#33）：
   - 主要入口是貼上 Google Maps 連結。App 只解析使用者貼上的網址文字（短網址先轉成完整網址），不抓網頁內容，也不呼叫 Google API。原始連結一律保留。
   - 輔助入口是 OSM：地名搜尋用 Nominatim（只在按下搜尋時查，每秒最多 1 次），附近地點用 Overpass。兩者都帶能識別本 App 的 User-Agent。
   - 地圖用 `flutter_map` 加 `vector_map_tiles`，圖磚用 OpenFreeMap，用 `RichAttributionWidget` 顯示「OpenFreeMap © OpenMapTiles Data from OpenStreetMap」。整套不需要 API 金鑰。
   - `place_id` 欄位名稱不變，值加上來源前綴：`gmaps:<…>`、`osm:node:<id>`／`osm:way:<id>`／`osm:relation:<id>`、`custom:<隨機 id>`。沒有前綴的是既有的 Google Place ID。現有規則允許 1–300 字，不用改規則。
   - 從 Google Maps 連結解析出的座標視同 Google 的資料，沿用 `data-model.md` 的 30 天更新規定。`gmaps:` 地點的座標一定要附上取得時間（`coordinatesCachedAt`，伺服器時間），規則檢查。App 不能自己重抓，所以到期後刪除座標，只留連結和名稱，地點上顯示「位置已過期，重新貼上連結即可更新」，地圖上不顯示這個點（2026-11-12 修訂）。OSM 與自訂地點的座標沒有這個限制，但畫面要標示 OSM 來源（ODbL）。
3. **行程版本 `versions`**（0010）：版本文件 id 就是版號，格式 `v` 加 4 位數字（`v0001`）。規則檢查 `number` 與 id 一致、`v0001` 或上一版已存在、這一版尚未存在，建立後不能修改。兩人同時儲存時，後到的被拒絕，App 用下一號重試。不維護計數器文件，也不用 transaction。「儲存版本」只在連線時能按，離線時停用並說明原因（0004 的例外）。
4. **成員在線狀態**：照 0009 第 3 點，用 Realtime Database 的 `presence/{tripId}/{uid}` 與 `onDisconnect`。Spark 同時連線上限 100 個，測試階段夠用，超過前要升級。
5. **需要 Function 的功能，在 Spark 上的處理**：

| 功能 | 上線前 | Spark 上的做法 |
|---|---|---|
| 刪除帳號 | 必須 | 客戶端先刪除自己的個人資料與成員文件，再刪除 Auth 帳號。規則要允許本人刪除自己的文件。Google Play 規定必須提供 |
| 交接隊長 | 必須 | 兩步：隊長建立 `handover`（`pending`），對方接受後由他自己把 `trips.leaderId` 改成自己。規則用 `get()` 核對對應的 `handover` 是 `accepted` 而且 `toMemberId` 是本人 |
| 隊長未交接就刪除帳號 | 必須 | 不能等對方按接受，否則隊長可能永遠刪不掉帳號，違反 Google Play 的規定。旅程裡還有其他成員時，隊長刪除帳號的同一批寫入要指定新隊長：有副隊長就給副隊長，沒有就給最早加入的成員。寫入內容是 `handover`（`status = assigned`）、`trips.leaderId` 與新隊長成員文件的 `role = leader`，最後刪除自己的成員文件，不需要新隊長在線。規則核對四件事：對象是現有成員、不是未成年、同一批有對應的 `assigned` 交接，並用 `getAfter` 確認原隊長的成員文件在這次寫入後已不存在，所以只有刪除帳號時才能這樣強制轉移，平常的交接仍要對方按接受。新隊長下次打開 App 時看到 App 內提醒（Spark 上沒有推播）。規則沒辦法查「最早加入」，所以挑選順序由 App 負責。旅程只剩隊長一人時，刪除帳號的同時結束旅程（`leader_manual`）並刪除他的位置文件。所有 Firestore 寫入完成後才刪除 Auth 帳號（2026-11-12 修訂） |
| 退出旅程 | 必須 | 本人刪除自己的成員文件與自己的 `locations` 文件。隊長退出前必須先完成交接 |
| 旅程結束時清除位置 | 必須 | 取代 `clearLocationsWhenTripEnds`。規則在 `status == ended` 後拒絕所有人讀寫 `locations`，只留一條例外：本人可以用路徑 `trips/{tripId}/locations/{uid}` 刪除自己的文件，不需要先讀取。結束旅程的人在同一批寫入裡刪除自己的位置，其他成員下次打開 App 時刪除自己的 |
| 已結束舊旅程的位置資料 | 必須 | 一次性清理腳本，用 Admin SDK 刪除已結束旅程底下所有 `locations`，先試跑只列數量。需要專案管理權限，由治齊在自己的電腦上執行（2026-11-12 修訂） |
| 自動結束旅程 | 可佔位 | 取代 `endExpiredTrips`。成員打開 App 時，若已超過 `expectedReturnAt` 或結束日 23:59，就寫入 `ended`，`endReason` 寫 `expected_return` 或 `end_date`。規則用 `request.time` 判斷是否已過期，不信任手機的時間，手機時間調快也不能提早結束 |
| 單獨行動通知 | 可佔位 | 規則把關的客戶端寫入 `soloNotices`，未成年需要核准的流程照 0008 |
| 推播 | 可佔位 | Spark 上不做。改用 App 內提醒與分享到 LINE（0011） |
| 匿名帳號定期刪除（0012 第 5 點） | 上線前要決定 | 沒有排程就無法自動刪除。網頁版上線前，要嘛升 Blaze，要嘛改寫隱私權政策的保存期限 |

6. **找人地圖**（0002）：和第 2 點用同一套地圖。位置分享存在 Firestore 的 `locations`，不需要 Blaze。
## 理由
維持 Spark 可以讓測試期不用綁信用卡，也沒有被意外計費的風險。改成客戶端寫入的功能，規則本來就要驗證，所以沒有犧牲安全性；做不到的（推播、排程刪除）明確列出，不假裝做到。
## 後果／取捨
- 規則變得比較複雜：交接、退出、刪除帳號、版本、結束時清除位置都要加規則與測試（羽負責，菱驗收）。
- 「自動結束」與「清除位置」要等有成員打開 App 才會發生，時間不準。清除位置靠規則擋讀取，所以隱私上不會外洩，但資料會留在資料庫裡比較久，要寫進隱私權政策。
- OSM 的台灣小店資料比 Google 少，也沒有評分和照片，所以以貼 Google Maps 連結為主。
- Overpass、Nominatim、OpenFreeMap 都是公開服務、沒有服務等級保證，使用者變多後要自己架或改用付費服務。
- 升 Blaze 時，第 5 點標示「可佔位」的項目與匿名帳號刪除改回 Function，本 ADR 再修訂。
