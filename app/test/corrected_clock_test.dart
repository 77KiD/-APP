import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/core/time/time_rules.dart';

void main() {
  test('離線時改手機時間不影響儲存時間，只看 elapsedRealtime', () {
    final sample = TimeSample(
      serverNow: DateTime.utc(2026, 10, 26, 12),
      deviceNow: DateTime.utc(2026, 10, 26, 12),
      elapsedRealtime: const Duration(milliseconds: 1000),
    );
    final stamped = CorrectedClock.stamp(
      sample: sample,
      deviceNow: DateTime.utc(2026, 10, 26, 18),
      elapsedRealtime: const Duration(milliseconds: 2000),
    );
    expect(stamped, DateTime.utc(2026, 10, 26, 12, 0, 1));
  });

  test('離線期間重開機改用手機時間加上上次的時間差', () {
    final sample = TimeSample(
      serverNow: DateTime.utc(2026, 10, 26, 12, 5),
      deviceNow: DateTime.utc(2026, 10, 26, 12),
      elapsedRealtime: const Duration(seconds: 50),
    );
    final stamped = CorrectedClock.stamp(
      sample: sample,
      deviceNow: DateTime.utc(2026, 10, 26, 13),
      elapsedRealtime: const Duration(seconds: 1),
    );
    expect(stamped, DateTime.utc(2026, 10, 26, 13, 5));
  });
}
