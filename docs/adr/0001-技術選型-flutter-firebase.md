# 0001 技術選型：Flutter + Firebase + Google Maps Platform
- 狀態：已採納（2026-10-26）｜關聯：#1
## 背景
第一版只上 Android，但要保留日後上 iOS；需要即時同步、推播與伺服器端運算。
## 決策
用戶端 Flutter（Android 先行），地圖 `google_maps_flutter`。後端 Firebase：Auth、Firestore、Cloud Functions、FCM。地圖與交通用 Google Maps Platform（Directions／Routes、Distance Matrix）。
## 理由
單一程式碼可同時支援 Android／iOS；Firestore 即時同步與離線快取適合團體共編；Google 在台灣、日本、美國的交通資料完整。
## 後果／取捨
Google 不提供計程車／Uber 價格，第一版不顯示該價格。依賴 Google 付費 API，需控管呼叫量與成本。
