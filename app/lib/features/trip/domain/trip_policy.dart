import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/l10n/app_strings.dart';

class NewTripForm {
  const NewTripForm({
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.timeZone,
    required this.returnDate,
    required this.returnTime,
  });

  final String title;
  final String startDate;
  final String endDate;
  final String timeZone;
  final String returnDate;
  final String returnTime;
}

class ParsedNewTrip {
  const ParsedNewTrip({required this.form, this.expectedReturnAt, this.error});

  final NewTripForm form;
  final DateTime? expectedReturnAt;
  final String? error;
}

abstract final class TripPolicy {
  static ParsedNewTrip parseNewTrip(NewTripForm form, DateTime now) {
    final title = form.title.trim();
    if (title.isEmpty) {
      return ParsedNewTrip(form: form, error: AppStrings.emptyTitle);
    }
    if (title.length > 40) {
      return ParsedNewTrip(form: form, error: AppStrings.titleTooLong);
    }
    if (CalendarDate.parse(form.startDate) == null ||
        CalendarDate.parse(form.endDate) == null) {
      return ParsedNewTrip(form: form, error: AppStrings.invalidDate);
    }
    if (form.endDate.trim().compareTo(form.startDate.trim()) < 0) {
      return ParsedNewTrip(form: form, error: AppStrings.endBeforeStart);
    }
    if (!TripTime.isKnownZone(form.timeZone)) {
      return ParsedNewTrip(form: form, error: AppStrings.invalidTimeZone);
    }
    final returnDate = form.returnDate.trim();
    final returnTime = form.returnTime.trim();
    if (returnDate.isEmpty && returnTime.isEmpty) {
      return ParsedNewTrip(form: form);
    }
    if (returnDate.isEmpty || returnTime.isEmpty) {
      return ParsedNewTrip(form: form, error: AppStrings.incompleteReturn);
    }
    if (CalendarDate.parse(returnDate) == null) {
      return ParsedNewTrip(form: form, error: AppStrings.invalidDate);
    }
    if (ClockTime.parse(returnTime) == null) {
      return ParsedNewTrip(form: form, error: AppStrings.invalidTime);
    }
    final expected = TripTime.parseDateAndTime(
      returnDate,
      returnTime,
      form.timeZone,
    );
    if (expected == null) {
      return ParsedNewTrip(form: form, error: AppStrings.invalidTimeZone);
    }
    final tooEarly = expectedReturnRejection(expected, now);
    if (tooEarly != null) {
      return ParsedNewTrip(form: form, error: tooEarly);
    }
    return ParsedNewTrip(form: form, expectedReturnAt: expected);
  }

  /// 不能改成比現在早。留空代表清除，清除本身不被這條規則擋住。
  static String? expectedReturnRejection(DateTime? proposed, DateTime now) {
    if (proposed == null) return null;
    if (proposed.isBefore(now.toUtc())) return AppStrings.expectedReturnTooEarly;
    return null;
  }

  static bool canAssignViceCaptain(int memberCount) => memberCount >= 5;

  static bool viceCaptainRequiredToStart(int memberCount) => memberCount >= 8;

  static bool canStart(Iterable<MemberRole> roles, int memberCount) {
    if (!viceCaptainRequiredToStart(memberCount)) return true;
    return roles.contains(MemberRole.viceCaptain);
  }

  /// 有副隊長，或 2–4 人團：30 分鐘過期。
  /// 5–7 人且沒有副隊長：不過期。其餘情況（含 8 人以上還沒有副隊長）仍是 30 分鐘。
  static DateTime? requestExpiresAt({
    required int memberCount,
    required bool hasViceCaptain,
    required DateTime now,
  }) {
    final smallGroup = memberCount <= 4;
    if (smallGroup || hasViceCaptain) {
      return now.toUtc().add(const Duration(minutes: 30));
    }
    if (memberCount >= 5 && memberCount <= 7) return null;
    return now.toUtc().add(const Duration(minutes: 30));
  }
}
