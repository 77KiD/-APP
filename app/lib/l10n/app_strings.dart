/// 使用者看得到的字。介面一律繁體中文，用詞對齊 GLOSSARY.md。
abstract final class AppStrings {
  static const appTitle = '團體自由行';

  static const signInTitle = '登入';
  static const signUpTitle = '註冊';
  static const email = '電子郵件';
  static const password = '密碼';
  static const displayName = '顯示名稱';
  static const birthday = '出生日期';
  static const dateHint = 'YYYY-MM-DD';
  static const dateHelper = '用鍵盤輸入，格式 YYYY-MM-DD';
  static const timeHint = 'HH:mm';
  static const timeHelper = '24 小時制，例如 18:30';
  static const birthdayPurpose =
      '出生日期只用來確認年齡：未滿 13 歲無法註冊。已能註冊的人，是否未成年一律以 18 歲判斷。生日只存在你的帳號，不會放進旅程，其他成員只看得到你是否未成年。';
  static const birthdayConsent = '我已閱讀並同意為年齡驗證提供出生日期';
  static const submitSignUp = '同意並註冊';
  static const submitSignIn = '登入';
  static const goToSignUp = '還沒有帳號？前往註冊';
  static const goToSignIn = '已有帳號？前往登入';
  static const signOut = '登出';

  static const under13 = '未滿 13 歲無法註冊';
  static const needBirthdayConsent = '請先勾選同意提供出生日期';
  static const invalidEmail = '請輸入有效的電子郵件';
  static const weakPassword = '密碼至少需要 8 個字元';
  static const emptyName = '請輸入顯示名稱';
  static const nameTooLong = '顯示名稱最多 30 個字';
  static const invalidDate = '請用 YYYY-MM-DD 輸入日期';
  static const emailInUse = '這個電子郵件已經註冊';
  static const wrongCredentials = '電子郵件或密碼不正確';
  static const missingProfile = '找不到這個帳號的個人資料';

  static const consentTitle = '分析與當機報告';
  static const consentBody =
      'Firebase Analytics 與 Crashlytics 預設關閉。在你同意之前，不會收集使用統計，也不會上傳當機紀錄。你可以只同意其中一項。';
  static const analyticsSwitch = '同意啟用 Firebase Analytics';
  static const crashSwitch = '同意啟用 Crashlytics 當機報告';
  static const consentSave = '儲存我的選擇';
  static const consentDecline = '先不要，全部關閉';

  static const myTrips = '我的旅程';
  static const emptyTrips = '還沒有旅程。建立一趟旅程，或用邀請碼加入朋友的旅程。';
  static const createTrip = '建立旅程';
  static const joinTrip = '用邀請碼加入';
  static const locationDisclosureEntry = '定位與隱私說明';
  static const telemetrySettings = '分析與當機報告設定';
  static const dataInventoryEntry = '我們收集的資料';
  static const firebaseDevBanner =
      '尚未設定 Firebase，目前只把資料放在這台手機。正式環境會改走 Firebase，金鑰不會寫進版本庫。';

  static const tripTitle = '旅程名稱';
  static const startDate = '開始日期';
  static const endDate = '結束日期';
  static const timeZone = '旅程時區';
  static const timeZoneHelper = 'IANA 時區，例如 Asia/Taipei。結束日 23:59 依這個時區計算。';
  static const expectedReturn = '預計回程時間';
  static const expectedReturnOptional = '選填，大概的時間即可';
  static const returnDate = '預計回程日期';
  static const returnTime = '預計回程時間（幾點）';
  static const submitCreateTrip = '建立旅程';
  static const emptyTitle = '請輸入旅程名稱';
  static const titleTooLong = '旅程名稱最多 40 個字';
  static const endBeforeStart = '結束日期不能早於開始日期';
  static const invalidTime = '請用 HH:mm 輸入時間';
  static const incompleteReturn = '請同時填寫預計回程的日期與時間，或兩欄都留空';
  static const invalidTimeZone = '無法辨識這個旅程時區';
  static const expectedReturnTooEarly = '預計回程時間不能早於現在';
  static const expectedReturnKept = '沒有變更預計回程時間';
  static const expectedReturnUnset = '未填寫。旅程會在結束日 23:59（旅程時區）結束。';
  static const saveExpectedReturn = '儲存預計回程時間';
  static const clearExpectedReturn = '清除預計回程時間';
  static const submitReturnRequest = '送出預計回程時間修改申請';
  static const memberMustRequest = '一般成員要改預計回程時間，請送出修改申請';
  static const leadersSaveDirectly = '隊長與副隊長請直接儲存預計回程時間';

  static const inviteCode = '邀請碼';
  static const copyInvite = '複製邀請碼';
  static const copiedInvite = '已複製邀請碼';
  static const members = '成員';
  static const roleCaptain = '隊長';
  static const roleVice = '副隊長';
  static const roleMember = '一般成員';
  static const pendingRequests = '待同意的修改申請';
  static const noViceSmallGroup = '2 到 4 人的旅程只有隊長，不設副隊長';
  static const viceOptional = '5 到 7 人可以指定副隊長，不是必須';
  static const viceRequired = '8 人以上必須有副隊長才能開始旅程';
  static const onlyCaptainAssigns = '只有隊長可以指定副隊長';
  static const cannotDemoteCaptain = '不能把隊長改成副隊長';
  static String assignVice(String name) => '把$name設為副隊長';
  static String approveReturn(String when) => '同意 $when 的預計回程時間';
  static const rejectReturn = '拒絕這筆預計回程時間修改';
  static const requestExpired = '這筆申請已過期，預計回程時間維持原設定';
  static const requestHandled = '這筆申請已經處理過';
  static String requestExpires(String when) => '若無人同意，這筆申請會在 $when 過期';
  static const requestWaitsForLeader = '這筆申請會保留到隊長或副隊長回應';

  static const joinTitle = '加入旅程';
  static const inviteCodeField = '邀請碼';
  static const submitJoin = '加入旅程';
  static const emptyInvite = '請輸入邀請碼';
  static const inviteNotFound = '找不到這個邀請碼';
  static const alreadyMember = '你已經是這個旅程的成員';
  static const notMember = '你不是這個旅程的成員';
  static const joinNeedsNetwork = '加入旅程需要網路。邀請碼核對通過後，旅程會存到這台手機。';
  static const offlineMissing = '目前沒有網路，這趟旅程還沒有存在這台手機上';
  static const genericError = '發生問題，請再試一次';

  static const disclosureTitle = '定位權限說明';
  static const disclosureBody =
      '團體自由行只在你按下「發送定位」時，取得你當下的一個位置點，並分享給同一趟旅程的成員，用來在走散時找到彼此。\n\n我們不會在背景持續追蹤你的位置，也不會因為你只是打開 App 就向系統要求定位權限。從未按下「發送定位」的人不會出現在找人地圖上。旅程整團結束後，找人地圖上的位置會被清除。\n\n請先閱讀這段說明。按下下方按鈕只會記下你已閱讀，不會立刻跳出系統的權限視窗。';
  static const disclosureAck = '我已閱讀，稍後只在發送定位時授權';
  static const disclosureSaved = '已記下。我們現在不會向系統要求定位權限。';
  static const disclosureRequired = '請先閱讀定位權限說明，才能在發送定位時向系統要求權限';

  static const inventoryTitle = '我們收集的資料';
  static const inventoryIntro = '只收集旅程用得到的資料。沒有列出的東西這一版不收。';
  static const inventoryBirthday =
      '出生日期：判斷未滿 13 歲，以及已註冊者是否未成年（以 18 歲為準）。只存在你的帳號。';
  static const inventoryIdentity = '顯示名稱與頭像網址：讓同一趟旅程的同伴認得你。';
  static const inventoryLogin =
      '電子郵件與密碼：用來登入。密碼由 Firebase Authentication 保存，不放進行程資料。';
  static const inventoryTrip =
      '旅程與行程：名稱、開始與結束日期、旅程時區、預計回程時間、景點名稱、順序、時間、place_id，以及最多 30 天的座標。斷網時可以看行程清單。不把 Google 路線、交通時間或地圖圖磚存下來。';
  static const inventoryLocation =
      '位置快照：只有按下「發送定位」才送出當下一個點。這一版還沒有發送定位的按鈕，也不申請定位權限。';
  static const inventoryFcm = 'FCM 權杖：推播才需要。這一版還不收集。';
  static const inventoryTelemetry =
      'Firebase Analytics 與 Crashlytics：預設關閉，你同意後才啟用。';

  static String avatarLabel(String name) => '$name的頭像';
  static String memberRowLabel(String name, String role) => '$name，$role';
}
