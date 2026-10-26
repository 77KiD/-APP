import 'package:timezone/timezone.dart' as tz;

/// 日曆日期，不含時分。生日與旅程起迄都用這個，避免 UTC 時戳把日期撥到前一天。
class CalendarDate {
  const CalendarDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  static final _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  static CalendarDate? parse(String raw) {
    final match = _pattern.firstMatch(raw.trim());
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (month < 1 || month > 12 || day < 1) return null;
    final checked = DateTime(year, month, day);
    if (checked.year != year || checked.month != month || checked.day != day) {
      return null;
    }
    return CalendarDate(year, month, day);
  }

  DateTime toLocalDate() => DateTime(year, month, day);

  String format() {
    final monthText = month.toString().padLeft(2, '0');
    final dayText = day.toString().padLeft(2, '0');
    return '$year-$monthText-$dayText';
  }
}

class ClockTime {
  const ClockTime(this.hour, this.minute);

  final int hour;
  final int minute;

  static final _pattern = RegExp(r'^(\d{1,2}):(\d{2})$');

  static ClockTime? parse(String raw) {
    final match = _pattern.firstMatch(raw.trim());
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return ClockTime(hour, minute);
  }
}

/// 未滿 13 歲不能註冊。已能註冊的人是否未成年，一律以 18 歲判斷。
abstract final class AgePolicy {
  static bool meetsAge(String birthday, DateTime today, int years) {
    final birth = CalendarDate.parse(birthday);
    if (birth == null) return false;
    final anniversary = _anniversary(birth, years);
    final current = DateTime(today.year, today.month, today.day);
    return !current.isBefore(anniversary);
  }

  static bool isUnder13(String birthday, DateTime today) =>
      !meetsAge(birthday, today, 13);

  static bool isMinor(String birthday, DateTime today) =>
      !meetsAge(birthday, today, 18);

  /// 2 月 29 日遇到非閏年，周年日算 3 月 1 日（與 Dart 的日期溢位相同）。
  static DateTime _anniversary(CalendarDate birth, int years) {
    final year = birth.year + years;
    final overflow = DateTime(year, birth.month, birth.day);
    return DateTime(overflow.year, overflow.month, overflow.day);
  }
}

/// 上次連線時記下的伺服器時間、手機時間，以及 Android elapsedRealtime。
class TimeSample {
  const TimeSample({
    required this.serverNow,
    required this.deviceNow,
    required this.elapsedRealtime,
  });

  final DateTime serverNow;
  final DateTime deviceNow;
  final Duration elapsedRealtime;

  Map<String, Object> toMap() => {
    'serverNow': serverNow.toUtc().toIso8601String(),
    'deviceNow': deviceNow.toUtc().toIso8601String(),
    'elapsedMs': elapsedRealtime.inMilliseconds,
  };

  static TimeSample? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final server = DateTime.tryParse('${map['serverNow']}');
    final device = DateTime.tryParse('${map['deviceNow']}');
    final elapsed = map['elapsedMs'];
    if (server == null || device == null || elapsed is! num) return null;
    return TimeSample(
      serverNow: server.toUtc(),
      deviceNow: device.toUtc(),
      elapsedRealtime: Duration(milliseconds: elapsed.round()),
    );
  }
}

/// ADR 0004：離線儲存時間用上次同步的伺服器時間加上 elapsedRealtime 的差值。
/// 離線期間重開機（elapsedRealtime 變小）才改用手機時間加上時間差。
abstract final class CorrectedClock {
  static DateTime stamp({
    required TimeSample? sample,
    required DateTime deviceNow,
    required Duration elapsedRealtime,
  }) {
    if (sample == null) return deviceNow.toUtc();
    final rebooted = elapsedRealtime < sample.elapsedRealtime;
    if (rebooted) {
      final offset = sample.serverNow.difference(sample.deviceNow);
      return deviceNow.toUtc().add(offset);
    }
    return sample.serverNow
        .toUtc()
        .add(elapsedRealtime - sample.elapsedRealtime);
  }
}

abstract class DeviceClock {
  Future<DateTime> now();
  Future<Duration> elapsedRealtime();
}

class SystemDeviceClock implements DeviceClock {
  SystemDeviceClock({Duration Function()? elapsedFallback})
    : _elapsedFallback = elapsedFallback ?? _stopwatchElapsed;

  final Duration Function() _elapsedFallback;
  static final Stopwatch _stopwatch = Stopwatch()..start();

  static Duration _stopwatchElapsed() => _stopwatch.elapsed;

  @override
  Future<DateTime> now() async => DateTime.now();

  @override
  Future<Duration> elapsedRealtime() async => _elapsedFallback();
}

class FixedDeviceClock implements DeviceClock {
  FixedDeviceClock(this.current, {this.elapsed = Duration.zero});

  DateTime current;
  Duration elapsed;

  @override
  Future<DateTime> now() async => current;

  @override
  Future<Duration> elapsedRealtime() async => elapsed;
}

/// 預計回程時間與行程日期都解讀成旅程時區，而不是手機目前所在的時區。
abstract final class TripTime {
  static DateTime? parseDateAndTime(String date, String time, String iana) {
    final day = CalendarDate.parse(date);
    final clock = ClockTime.parse(time);
    if (day == null || clock == null) return null;
    try {
      final location = tz.getLocation(iana.trim());
      return tz.TZDateTime(
        location,
        day.year,
        day.month,
        day.day,
        clock.hour,
        clock.minute,
      ).toUtc();
    } catch (_) {
      return null;
    }
  }

  static String format(DateTime instant, String iana) {
    final location = tz.getLocation(iana.trim());
    final local = tz.TZDateTime.from(instant.toUtc(), location);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  static bool isKnownZone(String iana) {
    try {
      tz.getLocation(iana.trim());
      return iana.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

abstract class TimeZoneSource {
  Future<String> localIana();
}

class FixedTimeZoneSource implements TimeZoneSource {
  FixedTimeZoneSource(this.iana);

  final String iana;

  @override
  Future<String> localIana() async => iana;
}
