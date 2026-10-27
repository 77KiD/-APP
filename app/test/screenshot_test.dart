import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/core/theme/app_theme.dart';
import 'package:group_trip/core/widgets/app_shell.dart';

/// Custom golden file comparator that allows small pixel differences due to
/// font rendering variations across environments. Allows up to 0.5% difference.
class TolerantGoldenFileComparator extends LocalFileComparator {
  TolerantGoldenFileComparator(super.testFile, {this.maxAllowedDiff = 0.005});

  final double maxAllowedDiff;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );

    if (!result.passed && result.diffPercent <= maxAllowedDiff) {
      debugPrint(
        'Golden diff ${result.diffPercent.toStringAsFixed(4)} '
        'is within tolerance $maxAllowedDiff for $golden',
      );
      return true;
    }

    if (!result.passed) {
      final error = await generateFailureOutput(result, golden, basedir);
      throw FlutterError(error);
    }
    return result.passed;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    
    // Use tolerant comparator for font rendering differences
    goldenFileComparator = TolerantGoldenFileComparator(
      Uri.parse('test/screenshot_test.dart'),
      maxAllowedDiff: 0.005, // 0.5% tolerance for font rendering variations
    );
    
    // Load Nunito (headings) - variable font
    final nunitoLoader = FontLoader('Nunito')
      ..addFont(rootBundle.load('assets/fonts/Nunito-Variable.ttf'));
    await nunitoLoader.load();
    
    // Load DM Sans (body text) - variable font
    final dmSansLoader = FontLoader('DMSans')
      ..addFont(rootBundle.load('assets/fonts/DMSans-Variable.ttf'));
    await dmSansLoader.load();
    
    // Load Noto Sans TC (CJK fallback) - variable font with full Chinese support
    final notoTCLoader = FontLoader('NotoSansTC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansTC-Variable.ttf'));
    await notoTCLoader.load();
    
    // Also register Noto Sans TC as fallback for Nunito and DMSans
    // This ensures Chinese text renders even when primary fonts don't have the glyphs
    final notoFallbackNunito = FontLoader('Nunito')
      ..addFont(rootBundle.load('assets/fonts/NotoSansTC-Variable.ttf'));
    await notoFallbackNunito.load();
    
    final notoFallbackDMSans = FontLoader('DMSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSansTC-Variable.ttf'));
    await notoFallbackDMSans.load();
    
    // Load MaterialIcons from Flutter SDK
    final materialIconsPath = '${Directory.current.path}/../flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
    final materialIconsFile = File(materialIconsPath);
    
    if (await materialIconsFile.exists()) {
      final materialIconsLoader = FontLoader('MaterialIcons')
        ..addFont(Future.value(await materialIconsFile.readAsBytes()).then((bytes) => ByteData.view(Uint8List.fromList(bytes).buffer)));
      await materialIconsLoader.load();
    } else {
      // Try alternative path (in tmp where we installed Flutter)
      final altPath = '/tmp/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
      final altFile = File(altPath);
      if (await altFile.exists()) {
        final materialIconsLoader = FontLoader('MaterialIcons')
          ..addFont(Future.value(await altFile.readAsBytes()).then((bytes) => ByteData.view(Uint8List.fromList(bytes).buffer)));
        await materialIconsLoader.load();
      }
    }
  });

  testWidgets('Screenshot: Light theme 100%', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const AppShell(
          currentTrip: '東京自由行 2026',
          chatUnreadCount: 2,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/light_100.png'),
    );
  });

  testWidgets('Screenshot: Light theme 150%', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: const AppShell(
            currentTrip: '東京自由行 2026',
            chatUnreadCount: 2,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/light_150.png'),
    );
  });

  testWidgets('Screenshot: Dark theme 100%', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: const AppShell(
          currentTrip: '東京自由行 2026',
          chatUnreadCount: 2,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dark_100.png'),
    );
  });

  testWidgets('Screenshot: Dark theme 150%', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: const AppShell(
            currentTrip: '東京自由行 2026',
            chatUnreadCount: 2,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dark_150.png'),
    );
  });
}
