import 'package:group_trip/core/ids/id_generator.dart';
import 'package:group_trip/core/location/location_permission_gateway.dart';
import 'package:group_trip/core/share/share_gateway.dart';
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
    this.share = const SystemShareGateway(),
    this.isWeb = false,
    this.initialInviteCode,
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

  /// 系統分享選單（分享到 LINE）。
  final ShareGateway share;

  /// 網頁版只做看行程、投票、填資料卡、看帳（ADR 0012 第 2 點）。
  final bool isWeb;

  /// 從邀請連結 `/j/<邀請碼>` 打開時帶入的碼，加入頁會先填好。
  final String? initialInviteCode;
}
