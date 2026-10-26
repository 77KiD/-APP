import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:group_trip/core/firebase/firebase_config.dart';

/// 只在編譯參數齊全時初始化。Analytics 與 Crashlytics 先強制關閉，
/// 之後由 [Telemetry.apply] 依同意結果打開。
Future<void> initializeConfiguredFirebase() async {
  if (!FirebaseConfig.isConfigured) {
    throw StateError('Firebase 尚未設定');
  }
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: FirebaseConfig.apiKey,
      appId: FirebaseConfig.appId,
      messagingSenderId: FirebaseConfig.messagingSenderId,
      projectId: FirebaseConfig.projectId,
      storageBucket: FirebaseConfig.storageBucket.isEmpty
          ? null
          : FirebaseConfig.storageBucket,
    ),
  );
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: FirebaseConfig.firestorePersistenceEnabled,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
}
