import 'package:group_trip/core/ids/id_generator.dart';
import 'package:group_trip/core/location/location_permission_gateway.dart';
import 'package:group_trip/core/telemetry/telemetry.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/features/auth/domain/auth_models.dart';
import 'package:group_trip/features/location_disclosure/data/disclosure_store.dart';
import 'package:group_trip/features/trip/data/offline_trip_repository.dart';
import 'package:group_trip/features/trip/domain/trip_repository.dart';

class AppDependencies {
  AppDependencies({
    required this.auth,
    required this.trips,
    required this.telemetry,
    required this.clock,
    required this.timeZone,
    required this.disclosure,
    required this.location,
    required this.connectivity,
    required this.ids,
    required this.firebaseConfigured,
  });

  final AuthRepository auth;
  final TripRepository trips;
  final Telemetry telemetry;
  final DeviceClock clock;
  final TimeZoneSource timeZone;
  final DisclosureStore disclosure;
  final LocationPermissionGateway location;
  final ConnectivityProbe connectivity;
  final IdGenerator ids;
  final bool firebaseConfigured;
}
