import 'package:flutter/foundation.dart';

/// Firebase 設定只從編譯參數讀，版本庫不放真的金鑰。
///
/// ```
/// flutter run \
///   --dart-define=FIREBASE_API_KEY=... \
///   --dart-define=FIREBASE_APP_ID=... \
///   --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
///   --dart-define=FIREBASE_PROJECT_ID=... \
///   --dart-define=FIREBASE_STORAGE_BUCKET=...
/// ```
///
/// 網頁版另外需要 `FIREBASE_WEB_APP_ID`。
abstract final class FirebaseConfig {
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );

  /// Firebase 主控台裡「網頁應用程式」的 App ID，跟 Android 的不同（ADR 0012）。
  static const webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');

  /// 網頁版有設定 [webAppId] 就用它，否則用 [appId]。
  static String get effectiveAppId =>
      kIsWeb && webAppId.isNotEmpty ? webAppId : appId;

  static bool get isConfigured =>
      apiKey.isNotEmpty &&
      effectiveAppId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      projectId.isNotEmpty;

  /// Firestore 離線持久化。Android 上由 [FirebaseInitializer] 寫進 Settings。
  static const bool firestorePersistenceEnabled = true;
}
