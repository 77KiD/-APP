import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/core/firebase/firebase_config.dart';
import 'package:group_trip/features/trip/data/firestore_paths.dart';

void main() {
  test('沒有編譯參數時不初始化 Firebase，Firestore 離線持久化維持開啟', () {
    expect(FirebaseConfig.isConfigured, isFalse);
    expect(FirebaseConfig.apiKey, isEmpty);
    expect(FirebaseConfig.firestorePersistenceEnabled, isTrue);
  });

  test('資料路徑以旅程為根', () {
    expect(FirestorePaths.trips, 'trips');
    expect(FirestorePaths.members, 'members');
    expect(FirestorePaths.requests, 'requests');
    expect(FirestorePaths.itineraryHistory, 'itineraryHistory');
    expect(FirestorePaths.handover, 'handover');
    expect(FirestorePaths.soloNotices, 'soloNotices');
    expect(FirestorePaths.inviteCodes, 'inviteCodes');
    expect(FirestorePaths.users, 'users');
    expect(FirestorePaths.all, contains(FirestorePaths.locations));
  });
}
