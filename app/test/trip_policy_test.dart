import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/l10n/app_strings.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  final now = DateTime.utc(2026, 10, 26, 1);

  test('預計回程時間早於現在會被擋下，剛好現在可以', () {
    expect(
      TripPolicy.expectedReturnRejection(
        now.subtract(const Duration(seconds: 1)),
        now,
      ),
      AppStrings.expectedReturnTooEarly,
    );
    expect(TripPolicy.expectedReturnRejection(now, now), isNull);
    expect(TripPolicy.expectedReturnRejection(null, now), isNull);
  });

  test('5 到 7 人沒有副隊長時修改申請不過期', () {
    expect(
      TripPolicy.requestExpiresAt(
        memberCount: 4,
        hasViceCaptain: false,
        now: now,
      ),
      now.add(const Duration(minutes: 30)),
    );
    expect(
      TripPolicy.requestExpiresAt(
        memberCount: 6,
        hasViceCaptain: false,
        now: now,
      ),
      isNull,
    );
    expect(
      TripPolicy.requestExpiresAt(memberCount: 6, hasViceCaptain: true, now: now),
      isNotNull,
    );
    expect(
      TripPolicy.requestExpiresAt(
        memberCount: 8,
        hasViceCaptain: false,
        now: now,
      ),
      isNotNull,
    );
  });

  test('8 人以上沒有副隊長不能開始', () {
    expect(
      TripPolicy.canStart([MemberRole.captain, MemberRole.member], 8),
      isFalse,
    );
    expect(
      TripPolicy.canStart([
        MemberRole.captain,
        MemberRole.viceCaptain,
      ], 8),
      isTrue,
    );
    expect(TripPolicy.canAssignViceCaptain(4), isFalse);
    expect(TripPolicy.canAssignViceCaptain(5), isTrue);
  });

  test('公開邀請與邀請碼滿 1 小時的邊界', () {
    expect(
      TripPolicy.canIssueInvite(role: MemberRole.member, publicInvite: true),
      isTrue,
    );
    expect(
      TripPolicy.canIssueInvite(role: MemberRole.member, publicInvite: false),
      isFalse,
    );
    expect(
      TripPolicy.canIssueInvite(
        role: MemberRole.viceCaptain,
        publicInvite: false,
      ),
      isTrue,
    );
    expect(
      TripPolicy.canIssueInvite(role: MemberRole.captain, publicInvite: false),
      isTrue,
    );
    final expires = TripPolicy.inviteExpiresAt(now);
    expect(
      TripPolicy.isInviteExpired(
        expires,
        expires.subtract(const Duration(milliseconds: 1)),
      ),
      isFalse,
    );
    expect(TripPolicy.isInviteExpired(expires, expires), isTrue);
    expect(
      TripPolicy.isInviteExpired(
        expires,
        expires.add(const Duration(milliseconds: 1)),
      ),
      isTrue,
    );
  });
}
