import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:group_trip/app/app_dependencies.dart';
import 'package:group_trip/core/firebase/firebase_config.dart';
import 'package:group_trip/core/firebase/firebase_initializer.dart';
import 'package:group_trip/core/ids/id_generator.dart';
import 'package:group_trip/core/location/location_permission_gateway.dart';
import 'package:group_trip/core/persistence/json_document_store.dart';
import 'package:group_trip/core/telemetry/telemetry.dart';
import 'package:group_trip/core/time/device_sources.dart';
import 'package:group_trip/features/auth/data/firebase_auth_repository.dart';
import 'package:group_trip/features/auth/data/local_auth_repository.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/location_disclosure/data/disclosure_store.dart';
import 'package:group_trip/features/trip/data/firestore_trip_remote.dart';
import 'package:group_trip/features/trip/data/memory_trip_remote.dart';
import 'package:group_trip/features/trip/data/offline_trip_repository.dart';
import 'package:group_trip/features/trip/data/trip_local_store.dart';
import 'package:path_provider/path_provider.dart';

Future<AppDependencies> buildAppDependencies() async {
  final configured = FirebaseConfig.isConfigured;
  if (configured) await initializeConfiguredFirebase();

  final directory = await getApplicationSupportDirectory();
  final ids = RandomIdGenerator();
  final clock = AndroidElapsedClock();
  final connectivity = PluginConnectivityProbe();

  final AuthRepository auth;
  if (configured) {
    final firebaseAuth = FirebaseAuthRepository();
    await firebaseAuth.restore();
    auth = firebaseAuth;
  } else {
    final localAuth = LocalAuthRepository(
      store: FileDocumentStore(File('${directory.path}/auth.json')),
      ids: ids,
    );
    await localAuth.restore();
    auth = localAuth;
  }

  final trips = OfflineTripRepository(
    local: TripLocalStore(
      FileDocumentStore(File('${directory.path}/trips.json')),
    ),
    remote: configured
        ? FirestoreTripRemote(currentUserId: () => auth.current?.id ?? '')
        : MemoryTripRemote(
            database: MemoryTripDatabase(),
            currentUserId: () => auth.current?.id ?? '',
          ),
    currentAccount: () => auth.current,
    clock: clock,
    ids: ids,
    connectivity: connectivity,
  );
  final disclosure = DisclosureStore(
    FileDocumentStore(File('${directory.path}/disclosure.json')),
  );
  final telemetry = Telemetry(
    analytics: configured
        ? const FirebaseAnalyticsClient()
        : RecordingAnalyticsClient(),
    crashes: configured
        ? const FirebaseCrashReporterClient()
        : RecordingCrashReporter(),
  );
  final account = auth.current;
  await applyInitialTelemetry(
    telemetry: telemetry,
    consentDecided: account?.consentDecided ?? false,
    analyticsConsent: account?.analyticsConsent ?? false,
    crashlyticsConsent: account?.crashlyticsConsent ?? false,
  );

  return AppDependencies(
    auth: auth,
    trips: trips,
    telemetry: telemetry,
    clock: clock,
    timeZone: DeviceTimeZoneSource(),
    disclosure: disclosure,
    location: LocationPermissionGateway(
      hasAcknowledgedDisclosure: () async {
        final userId = auth.current?.id;
        if (userId == null) return false;
        return disclosure.isAcknowledged(userId);
      },
      client: const UnavailableLocationPermissionClient(),
    ),
    connectivity: connectivity,
    ids: ids,
    firebaseConfigured: configured,
  );
}

class FirebaseAnalyticsClient implements AnalyticsClient {
  const FirebaseAnalyticsClient();

  @override
  Future<void> setCollectionEnabled(bool enabled) {
    return FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(enabled);
  }

  @override
  Future<void> logEvent(String name, [Map<String, Object>? parameters]) {
    return FirebaseAnalytics.instance.logEvent(
      name: name,
      parameters: parameters,
    );
  }
}

class FirebaseCrashReporterClient implements CrashReporter {
  const FirebaseCrashReporterClient();

  @override
  Future<void> setCollectionEnabled(bool enabled) {
    return FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled);
  }

  @override
  Future<void> recordError(Object error, StackTrace stack) {
    return FirebaseCrashlytics.instance.recordError(error, stack);
  }
}

/// 這一版沒有「發送定位」，不向系統要定位權限。
class UnavailableLocationPermissionClient implements LocationPermissionClient {
  const UnavailableLocationPermissionClient();

  @override
  Future<bool> requestForeground() async => false;
}
