import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/features/trip/data/offline_trip_repository.dart';

class AndroidElapsedClock extends SystemDeviceClock {
  static const _channel = MethodChannel('group_trip/clock');

  @override
  Future<Duration> elapsedRealtime() async {
    try {
      final milliseconds = await _channel.invokeMethod<int>('elapsedRealtime');
      if (milliseconds != null) return Duration(milliseconds: milliseconds);
    } catch (_) {
      // 測試或還沒接上 Android 時，退回這個行程的碼表。正式機會走 elapsedRealtime。
    }
    return super.elapsedRealtime();
  }
}

class DeviceTimeZoneSource implements TimeZoneSource {
  @override
  Future<String> localIana() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      if (info.identifier.isNotEmpty) return info.identifier;
    } catch (_) {
      // 拿不到 IANA 名稱時讓使用者在建立旅程的欄位改。
    }
    return 'UTC';
  }
}

class PluginConnectivityProbe extends ConnectivityProbe {
  @override
  Future<void> refresh() async {
    try {
      final results = await Connectivity().checkConnectivity();
      isOnline = results.any((result) => result != ConnectivityResult.none);
    } catch (_) {
      isOnline = true;
    }
  }
}
