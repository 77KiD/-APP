import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/app/app_dependencies.dart';
import 'package:group_trip/app/app_scope.dart';
import 'package:group_trip/core/ids/id_generator.dart';
import 'package:group_trip/core/location/location_permission_gateway.dart';
import 'package:group_trip/core/persistence/json_document_store.dart';
import 'package:group_trip/core/telemetry/telemetry.dart';
import 'package:group_trip/core/theme/app_theme.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/features/auth/data/local_auth_repository.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/location_disclosure/data/disclosure_store.dart';
import 'package:group_trip/features/trip/data/memory_trip_remote.dart';
import 'package:group_trip/features/trip/data/offline_trip_repository.dart';
import 'package:group_trip/features/trip/data/trip_local_store.dart';
import 'package:timezone/data/latest.dart' as tzdata;

class TestWorld {
  TestWorld({DateTime? now, bool online = true}) {
    tzdata.initializeTimeZones();
    clock = FixedDeviceClock(now ?? DateTime.utc(2026, 10, 26, 1));
    connectivity = ConnectivityProbe(isOnline: online);
    database = MemoryTripDatabase()..clock = clock.current;
    auth = LocalAuthRepository(
      store: MemoryDocumentStore(),
      ids: SequentialIdGenerator(),
    );
    remote = MemoryTripRemote(
      database: database,
      currentUserId: () => auth.current?.id ?? '',
    );
    trips = OfflineTripRepository(
      local: TripLocalStore(MemoryDocumentStore()),
      remote: remote,
      currentAccount: () => auth.current,
      clock: clock,
      ids: SequentialIdGenerator(),
      connectivity: connectivity,
    );
    analytics = RecordingAnalyticsClient();
    crashes = RecordingCrashReporter();
    telemetry = Telemetry(analytics: analytics, crashes: crashes);
    disclosure = DisclosureStore(MemoryDocumentStore());
    permissionClient = DenialLocationPermissionClient();
    deps = AppDependencies(
      auth: auth,
      trips: trips,
      telemetry: telemetry,
      clock: clock,
      timeZone: FixedTimeZoneSource('Asia/Taipei'),
      disclosure: disclosure,
      location: LocationPermissionGateway(
        hasAcknowledgedDisclosure: () async {
          final id = auth.current?.id;
          if (id == null) return false;
          return disclosure.isAcknowledged(id);
        },
        client: permissionClient,
      ),
      connectivity: connectivity,
      ids: SequentialIdGenerator(),
      firebaseConfigured: false,
    );
  }

  late final FixedDeviceClock clock;
  late final ConnectivityProbe connectivity;
  late final MemoryTripDatabase database;
  late final LocalAuthRepository auth;
  late final MemoryTripRemote remote;
  late final OfflineTripRepository trips;
  late final RecordingAnalyticsClient analytics;
  late final RecordingCrashReporter crashes;
  late final Telemetry telemetry;
  late final DisclosureStore disclosure;
  late final DenialLocationPermissionClient permissionClient;
  late final AppDependencies deps;

  UserAccount account({
    String id = 'user',
    String name = '小明',
    String birthday = '2000-01-01',
  }) {
    return UserAccount(
      id: id,
      email: '$id@example.com',
      displayName: name,
      birthday: birthday,
      consentDecided: true,
      analyticsConsent: false,
      crashlyticsConsent: false,
    );
  }

  OfflineTripRepository repositoryFor(
    UserAccount person, {
    TripLocalStore? local,
    DeviceClock? deviceClock,
  }) {
    return OfflineTripRepository(
      local: local ?? TripLocalStore(MemoryDocumentStore()),
      remote: MemoryTripRemote(
        database: database,
        currentUserId: () => person.id,
      ),
      currentAccount: () => person,
      clock: deviceClock ?? clock,
      ids: SequentialIdGenerator(),
      connectivity: connectivity,
    );
  }
}

Widget wrapPage(AppDependencies deps, Widget home) {
  return AppScope(
    deps: deps,
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('zh', 'TW'),
      supportedLocales: const [Locale('zh', 'TW')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  );
}

Finder labeledField(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

Future<void> enterLabeled(
  WidgetTester tester,
  String label,
  String value,
) async {
  final finder = labeledField(label);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
}
