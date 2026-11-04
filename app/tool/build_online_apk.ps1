# 建置連線版 APK。先檢查 Firebase 設定齊全，缺任何一項就停下，
# 避免再產出沒有 FIREBASE_* 編譯參數、只能在單機使用的版本。
#
# 用法（在 app/ 底下）：
#   pwsh tool/build_online_apk.ps1
#   pwsh tool/build_online_apk.ps1 -DefinesFile path/to/firebase.local.json
#
# firebase.local.json 與 android/app/google-services.json 都不提交到 git。
param(
  [string]$DefinesFile = (Join-Path $PSScriptRoot '..\firebase.local.json'),
  [string]$GoogleServices = (Join-Path $PSScriptRoot '..\android\app\google-services.json'),
  [string]$PackageName = 'com.example.group_trip'
)

$ErrorActionPreference = 'Stop'

function Fail([string]$message) {
  Write-Error "build_online_apk: $message"
  exit 1
}

if (-not (Test-Path -LiteralPath $DefinesFile)) {
  Fail "找不到 $DefinesFile。複製 firebase.local.example.json 成 firebase.local.json 並填入 Firebase 設定。"
}
$defines = Get-Content -LiteralPath $DefinesFile -Raw | ConvertFrom-Json

# 跟 FirebaseConfig.isConfigured 一致：這四項都有值才會連上 Firebase。
$required = @(
  'FIREBASE_API_KEY',
  'FIREBASE_APP_ID',
  'FIREBASE_MESSAGING_SENDER_ID',
  'FIREBASE_PROJECT_ID'
)
$missing = @($required | Where-Object {
  $value = $defines.$_
  -not $value -or "$value".Trim() -eq '' -or "$value".StartsWith('REPLACE_')
})
if ($missing.Count -gt 0) {
  Fail "firebase.local.json 缺少：$($missing -join ', ')。少任何一項，App 都會是本機模式，邀請碼無法跨手機。"
}

if (-not (Test-Path -LiteralPath $GoogleServices)) {
  Fail "找不到 $GoogleServices。從 Firebase 主控台下載 Android 的 google-services.json 放到這裡。"
}
$services = Get-Content -LiteralPath $GoogleServices -Raw | ConvertFrom-Json
$servicesProject = $services.project_info.project_id
if ($servicesProject -ne $defines.FIREBASE_PROJECT_ID) {
  Fail "google-services.json 的 project_id（$servicesProject）跟 FIREBASE_PROJECT_ID（$($defines.FIREBASE_PROJECT_ID)）不同。"
}
$packages = @($services.client | ForEach-Object { $_.client_info.android_client_info.package_name })
if ($packages -notcontains $PackageName) {
  Fail "google-services.json 裡沒有套件 $PackageName（有：$($packages -join ', ')）。"
}

Write-Host "Firebase 設定檢查通過：project $servicesProject，套件 $PackageName。開始建置。"
Push-Location (Join-Path $PSScriptRoot '..')
try {
  flutter build apk --release "--dart-define-from-file=$((Resolve-Path -LiteralPath $DefinesFile).Path)"
  if ($LASTEXITCODE -ne 0) { Fail "flutter build apk 失敗（exit $LASTEXITCODE）。" }
} finally {
  Pop-Location
}
Write-Host '完成：build/app/outputs/flutter-apk/app-release.apk'
