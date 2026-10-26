import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/core/location/location_permission_gateway.dart';
import 'package:group_trip/core/telemetry/telemetry.dart';
import 'package:group_trip/l10n/app_strings.dart';

void main() {
  test('同意前不啟用 Analytics 與 Crashlytics，也不送事件', () async {
    final analytics = RecordingAnalyticsClient();
    final crashes = RecordingCrashReporter();
    final telemetry = Telemetry(analytics: analytics, crashes: crashes);
    final previous = FlutterError.onError;
    await applyInitialTelemetry(
      telemetry: telemetry,
      consentDecided: false,
      analyticsConsent: true,
      crashlyticsConsent: true,
    );
    await telemetry.log('trip_created');
    expect(analytics.enabled, isFalse);
    expect(crashes.enabled, isFalse);
    expect(analytics.events, isEmpty);
    expect(analytics.enableCalls, [false]);
    expect(crashes.enableCalls, [false]);

    await telemetry.apply(analytics: true, crashlytics: false);
    await telemetry.log('trip_created');
    expect(analytics.events, ['trip_created']);
    expect(crashes.enabled, isFalse);
    FlutterError.onError = previous;
  });

  test('沒讀過定位說明就不能要求權限', () async {
    final client = DenialLocationPermissionClient();
    var acknowledged = false;
    final gateway = LocationPermissionGateway(
      hasAcknowledgedDisclosure: () async => acknowledged,
      client: client,
    );
    await expectLater(
      gateway.requestForSendLocation(),
      throwsA(isA<LocationDisclosureRequired>()),
    );
    expect(client.calls, 0);
    acknowledged = true;
    expect(await gateway.requestForSendLocation(), isFalse);
    expect(client.calls, 1);
    expect(LocationDisclosureRequired().toString(), AppStrings.disclosureRequired);
  });
}
