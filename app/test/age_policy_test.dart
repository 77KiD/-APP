import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/core/time/time_rules.dart';

void main() {
  final today = DateTime(2026, 10, 26);

  test('生日當天滿 13 歲可以註冊，前一天不行', () {
    expect(AgePolicy.isUnder13('2013-10-26', today), isFalse);
    expect(AgePolicy.isUnder13('2013-10-27', today), isTrue);
    expect(AgePolicy.isUnder13('2013-10-25', today), isFalse);
  });

  test('未滿 13 歲不能註冊，滿 13 但未滿 18 仍是未成年', () {
    expect(AgePolicy.isUnder13('2015-01-01', today), isTrue);
    expect(AgePolicy.isMinor('2015-01-01', today), isTrue);
    expect(AgePolicy.isUnder13('2008-10-26', today), isFalse);
    expect(AgePolicy.isMinor('2008-10-26', today), isFalse);
    expect(AgePolicy.isMinor('2008-10-27', today), isTrue);
  });

  test('2 月 29 日出生，非閏年要到 3 月 1 日才滿歲', () {
    expect(AgePolicy.isUnder13('2012-02-29', DateTime(2025, 2, 28)), isTrue);
    expect(AgePolicy.isUnder13('2012-02-29', DateTime(2025, 3, 1)), isFalse);
  });

  test('不接受不存在的日期', () {
    expect(CalendarDate.parse('2026-02-31'), isNull);
    expect(CalendarDate.parse('2026-13-01'), isNull);
    expect(AgePolicy.isUnder13('not-a-date', today), isTrue);
  });
}
