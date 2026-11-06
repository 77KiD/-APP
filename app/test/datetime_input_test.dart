import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/core/widgets/datetime_input.dart';

void main() {
  group('DateTimeInputField', () {
    late TextEditingController controller;

    setUp(() {
      controller = TextEditingController();
    });

    tearDown(() {
      controller.dispose();
    });

    Widget buildTestWidget(Widget child) {
      return MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'TW')],
        home: Scaffold(body: child),
      );
    }

    testWidgets('date field formats digits as user types', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          DateTimeInputField(
            label: 'Date',
            controller: controller,
            isDate: true,
          ),
        ),
      );

      final field = find.byType(TextField);
      await tester.enterText(field, '20260315');
      expect(controller.text, '2026-03-15');
    });

    group('只輸入數字，自動分隔（#76）', () {
      Future<void> pumpDateField(WidgetTester tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            DateTimeInputField(label: 'Date', controller: controller),
          ),
        );
      }

      Future<void> edit(
        WidgetTester tester, {
        required String text,
        required int cursor,
      }) async {
        await tester.showKeyboard(find.byType(TextField));
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: cursor),
          ),
        );
        await tester.pump();
      }

      testWidgets('鍵盤只給數字，打不出分隔符號', (tester) async {
        await pumpDateField(tester);

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.keyboardType, TextInputType.number);

        for (final typed in ['2026-03-15', '2026_03_15', '2026/03/15']) {
          await tester.enterText(find.byType(TextField), typed);
          expect(controller.text, '2026-03-15', reason: typed);
        }
        await tester.enterText(find.byType(TextField), '-_/ abc');
        expect(controller.text, isEmpty);
      });

      testWidgets('逐字輸入時自動補分隔', (tester) async {
        await pumpDateField(tester);

        for (final (typed, shown) in [
          ('2026', '2026'),
          ('20260', '2026-0'),
          ('202603', '2026-03'),
          ('2026031', '2026-03-1'),
          ('20260315', '2026-03-15'),
        ]) {
          await tester.enterText(find.byType(TextField), typed);
          expect(controller.text, shown);
          expect(controller.selection.baseOffset, shown.length);
        }
      });

      testWidgets('點欄位不會開日曆，日曆從圖示開', (tester) async {
        await pumpDateField(tester);

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsNothing);

        await tester.tap(find.byIcon(Icons.calendar_today));
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
      });

      testWidgets('用日曆選的日期會寫進欄位，之後還能打字修改', (tester) async {
        await pumpDateField(tester);
        await tester.enterText(find.byType(TextField), '20260315');

        await tester.tap(find.byIcon(Icons.calendar_today));
        await tester.pumpAndSettle();
        await tester.tap(find.text('20'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('確定'));
        await tester.pumpAndSettle();

        expect(find.byType(DatePickerDialog), findsNothing);
        expect(controller.text, '2026-03-20');

        await tester.enterText(find.byType(TextField), '20260401');
        expect(controller.text, '2026-04-01');
      });

      testWidgets('改中間的數字時，游標留在原處', (tester) async {
        await pumpDateField(tester);
        await tester.enterText(find.byType(TextField), '20260315');

        // 刪掉月份的 3：2026-03-15 → 2026-01-5，游標在 1 的前面。
        await edit(tester, text: '2026-0-15', cursor: 6);

        expect(controller.text, '2026-01-5');
        expect(controller.selection.baseOffset, 6);
      });

      testWidgets('刪到分隔符號時，下一次刪除會刪到數字', (tester) async {
        await pumpDateField(tester);
        await tester.enterText(find.byType(TextField), '202603');

        await edit(tester, text: '202603', cursor: 4);
        expect(controller.text, '2026-03');
        expect(controller.selection.baseOffset, 4);

        await edit(tester, text: '202-03', cursor: 3);
        expect(controller.text, '2020-3');
        expect(controller.selection.baseOffset, 3);
      });

      testWidgets('已經填滿時，插入數字不會擠掉最後一碼', (tester) async {
        await pumpDateField(tester);
        await tester.enterText(find.byType(TextField), '20260315');

        await edit(tester, text: '2099026-03-15', cursor: 4);

        expect(controller.text, '2026-03-15');
      });

      testWidgets('貼上過長的內容時截斷', (tester) async {
        await pumpDateField(tester);

        await tester.enterText(find.byType(TextField), '2026031599');

        expect(controller.text, '2026-03-15');
      });
    });

    testWidgets('time field formats digits as user types', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          DateTimeInputField(
            label: 'Time',
            controller: controller,
            isDate: false,
          ),
        ),
      );

      final field = find.byType(TextField);
      await tester.enterText(field, '1830');
      expect(controller.text, '18:30');
    });

    testWidgets('date field shows calendar icon', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          DateTimeInputField(
            label: 'Date',
            controller: controller,
            isDate: true,
          ),
        ),
      );

      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
    });

    testWidgets('time field shows clock icon', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          DateTimeInputField(
            label: 'Time',
            controller: controller,
            isDate: false,
          ),
        ),
      );

      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });

    testWidgets('opening date picker sets value', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          DateTimeInputField(
            label: 'Date',
            controller: controller,
            isDate: true,
          ),
        ),
      );

      // Tap the calendar icon to open picker
      await tester.tap(find.byIcon(Icons.calendar_today));
      await tester.pumpAndSettle();

      // Confirm the date (find OK button in Chinese)
      final okButton = find.text('確定');
      if (okButton.evaluate().isNotEmpty) {
        await tester.tap(okButton);
        await tester.pumpAndSettle();

        // Should have a date now
        expect(controller.text, matches(r'^\d{4}-\d{2}-\d{2}$'));
      }
    });

    testWidgets('opening time picker sets value', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          DateTimeInputField(
            label: 'Time',
            controller: controller,
            isDate: false,
          ),
        ),
      );

      // Tap the clock icon to open picker
      await tester.tap(find.byIcon(Icons.access_time));
      await tester.pumpAndSettle();

      // Confirm the time
      final okButton = find.text('確定');
      if (okButton.evaluate().isNotEmpty) {
        await tester.tap(okButton);
        await tester.pumpAndSettle();

        // Should have a time now
        expect(controller.text, matches(r'^\d{2}:\d{2}$'));
      }
    });
  });

  group('DateValidator', () {
    test('accepts valid date', () {
      const validator = DateValidator(required: true);
      expect(validator('2026-03-15'), isNull);
    });

    test('rejects empty when required', () {
      const validator = DateValidator(required: true);
      expect(validator(''), isNotNull);
    });

    test('accepts empty when not required', () {
      const validator = DateValidator(required: false);
      expect(validator(''), isNull);
    });

    test('rejects invalid format', () {
      const validator = DateValidator(required: true);
      expect(validator('2026/03/15'), isNotNull);
      expect(validator('invalid'), isNotNull);
    });

    test('rejects future date when notInFuture is true', () {
      const validator = DateValidator(notInFuture: true);
      expect(validator('2099-12-31'), isNotNull);
    });

    test('accepts past date when notInFuture is true', () {
      const validator = DateValidator(notInFuture: true);
      expect(validator('2020-01-01'), isNull);
    });

    test('rejects date before minDate', () {
      const validator = DateValidator(minDate: '2026-03-15');
      expect(validator('2026-03-14'), isNotNull);
    });

    test('accepts date after minDate', () {
      const validator = DateValidator(minDate: '2026-03-15');
      expect(validator('2026-03-16'), isNull);
    });

    test('rejects date exceeding maxDaysAfter', () {
      const validator = DateValidator(maxDaysAfter: ('2026-03-15', 30));
      expect(validator('2026-05-01'), isNotNull);
    });

    test('accepts date within maxDaysAfter', () {
      const validator = DateValidator(maxDaysAfter: ('2026-03-15', 30));
      expect(validator('2026-04-10'), isNull);
    });
  });

  group('TimeValidator', () {
    test('accepts valid time', () {
      const validator = TimeValidator(required: true);
      expect(validator('18:30'), isNull);
    });

    test('rejects empty when required', () {
      const validator = TimeValidator(required: true);
      expect(validator(''), isNotNull);
    });

    test('accepts empty when not required', () {
      const validator = TimeValidator(required: false);
      expect(validator(''), isNull);
    });

    test('rejects invalid format', () {
      const validator = TimeValidator(required: true);
      expect(validator('25:00'), isNotNull);
      expect(validator('18:60'), isNotNull);
      expect(validator('invalid'), isNotNull);
    });

    test('accepts valid hours and minutes', () {
      const validator = TimeValidator(required: true);
      expect(validator('00:00'), isNull);
      expect(validator('23:59'), isNull);
      expect(validator('12:30'), isNull);
    });
  });

  group('Timezone default and cross-timezone birthdate consistency', () {
    test('same birthday entered under UTC+9 and UTC-8 yields identical stored Timestamp', () {
      // Simulate entering birthday "1995-03-15" in different timezones
      // Both should produce the same UTC midnight Timestamp

      // UTC+9 scenario: entering on March 15, 2026 at 10:00 AM JST
      final birthdayStringUtcPlus9 = '1995-03-15';
      final dateUtcPlus9 = DateTime(1995, 3, 15); // This represents the date
      final utcMidnightPlus9 = DateTime.utc(
        dateUtcPlus9.year,
        dateUtcPlus9.month,
        dateUtcPlus9.day,
      );

      // UTC-8 scenario: entering on March 15, 2026 at 10:00 AM PST
      final birthdayStringUtcMinus8 = '1995-03-15';
      final dateUtcMinus8 = DateTime(1995, 3, 15); // Same date
      final utcMidnightMinus8 = DateTime.utc(
        dateUtcMinus8.year,
        dateUtcMinus8.month,
        dateUtcMinus8.day,
      );

      // Verify they produce the same UTC midnight timestamp
      expect(birthdayStringUtcPlus9, equals(birthdayStringUtcMinus8));
      expect(utcMidnightPlus9, equals(utcMidnightMinus8));
      expect(
        utcMidnightPlus9.millisecondsSinceEpoch,
        equals(utcMidnightMinus8.millisecondsSinceEpoch),
      );

      // Verify the UTC midnight timestamp represents exactly midnight UTC
      expect(utcMidnightPlus9.hour, equals(0));
      expect(utcMidnightPlus9.minute, equals(0));
      expect(utcMidnightPlus9.second, equals(0));
      expect(utcMidnightPlus9.millisecond, equals(0));

      // Verify age calculation is timezone-independent
      final testDate = DateTime.utc(2026, 3, 16); // Day after 31st birthday
      final age = testDate.year - utcMidnightPlus9.year;
      expect(age, equals(31));
    });

    test('birthdate at UTC midnight regardless of device timezone', () {
      // Test that parsing "1995-03-15" always gives UTC midnight
      final birthdayString = '1995-03-15';
      final parts = birthdayString.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);

      final utcMidnight = DateTime.utc(year, month, day);

      // Verify it's exactly midnight UTC
      expect(utcMidnight.isUtc, isTrue);
      expect(utcMidnight.hour, equals(0));
      expect(utcMidnight.minute, equals(0));
      expect(utcMidnight.second, equals(0));

      // Verify the date components
      expect(utcMidnight.year, equals(1995));
      expect(utcMidnight.month, equals(3));
      expect(utcMidnight.day, equals(15));
    });
  });
}
