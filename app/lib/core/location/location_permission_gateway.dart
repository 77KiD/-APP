import 'package:group_trip/l10n/app_strings.dart';

/// 真正向作業系統要定位權限的那一層。這一版的畫面不會呼叫它。
abstract class LocationPermissionClient {
  Future<bool> requestForeground();
}

class LocationDisclosureRequired implements Exception {
  @override
  String toString() => AppStrings.disclosureRequired;
}

class DenialLocationPermissionClient implements LocationPermissionClient {
  int calls = 0;

  @override
  Future<bool> requestForeground() async {
    calls += 1;
    return false;
  }
}

/// Google Play 的 prominent disclosure：先看過說明，之後才可以在「發送定位」要求權限。
class LocationPermissionGateway {
  LocationPermissionGateway({
    required this.hasAcknowledgedDisclosure,
    required this.client,
  });

  final Future<bool> Function() hasAcknowledgedDisclosure;
  final LocationPermissionClient client;

  Future<bool> requestForSendLocation() async {
    final acknowledged = await hasAcknowledgedDisclosure();
    if (!acknowledged) {
      throw LocationDisclosureRequired();
    }
    return client.requestForeground();
  }
}
