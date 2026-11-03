import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/features/trip/data/firestore_trip_remote.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/l10n/app_strings.dart';

void main() {
  FirebaseException firebase(String code) {
    return FirebaseException(
      plugin: 'cloud_firestore',
      code: code,
      message: code,
    );
  }

  test('permission-denied 且一般成員：公開邀請已關閉', () {
    final error = FirestoreTripRemote.exceptionForMemberJoinWrite(
      firebase('permission-denied'),
      MemberRole.member,
    );
    expect(error, isA<InviteClosedException>());
    expect(error.message, AppStrings.inviteClosedByPublicInvite);
  });

  test('permission-denied 的隊長或副隊長碼仍是原本的訊息', () {
    for (final role in [MemberRole.captain, MemberRole.viceCaptain]) {
      final error = FirestoreTripRemote.exceptionForMemberJoinWrite(
        firebase('permission-denied'),
        role,
      );
      expect(error, isA<InvitePermissionException>());
      expect(error.message, AppStrings.invitePermissionOrNetwork);
    }
  });

  test('斷線、逾時、unavailable 不會變成公開邀請已關閉', () {
    const codes = [
      'unavailable',
      'deadline-exceeded',
      'cancelled',
      'aborted',
      'internal',
      'unauthenticated',
      'unknown',
    ];
    for (final code in codes) {
      for (final role in MemberRole.values) {
        final error = FirestoreTripRemote.exceptionForMemberJoinWrite(
          firebase(code),
          role,
        );
        expect(
          error,
          isA<InvitePermissionException>(),
          reason: '$code ${role.name}',
        );
        expect(error.message, AppStrings.invitePermissionOrNetwork);
      }
    }
  });

  test('找不到與過期的訊息不變', () {
    expect(InviteNotFoundException().message, AppStrings.inviteNotFound);
    expect(InviteExpiredException().message, AppStrings.inviteExpired);
    expect(
      InvitePermissionException().message,
      AppStrings.invitePermissionOrNetwork,
    );
  });
}
