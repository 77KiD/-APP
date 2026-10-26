import 'package:flutter/foundation.dart';

abstract class AnalyticsClient {
  Future<void> setCollectionEnabled(bool enabled);

  Future<void> logEvent(String name, [Map<String, Object>? parameters]);
}

abstract class CrashReporter {
  Future<void> setCollectionEnabled(bool enabled);

  Future<void> recordError(Object error, StackTrace stack);
}

class RecordingAnalyticsClient implements AnalyticsClient {
  bool enabled = false;
  final events = <String>[];
  final enableCalls = <bool>[];

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    this.enabled = enabled;
    enableCalls.add(enabled);
  }

  @override
  Future<void> logEvent(String name, [Map<String, Object>? parameters]) async {
    if (!enabled) return;
    events.add(name);
  }
}

class RecordingCrashReporter implements CrashReporter {
  bool enabled = false;
  final enableCalls = <bool>[];
  final errors = <Object>[];

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    this.enabled = enabled;
    enableCalls.add(enabled);
  }

  @override
  Future<void> recordError(Object error, StackTrace stack) async {
    if (!enabled) return;
    errors.add(error);
  }
}

/// Analytics 與 Crashlytics 在同意前維持關閉。同意狀態由呼叫端傳入。
class Telemetry {
  Telemetry({required this.analytics, required this.crashes});

  final AnalyticsClient analytics;
  final CrashReporter crashes;
  bool analyticsAllowed = false;
  bool crashlyticsAllowed = false;
  FlutterExceptionHandler? _previousFlutterError;

  Future<void> apply({
    required bool analytics,
    required bool crashlytics,
  }) async {
    analyticsAllowed = analytics;
    crashlyticsAllowed = crashlytics;
    await this.analytics.setCollectionEnabled(analytics);
    await crashes.setCollectionEnabled(crashlytics);
    _installCrashHook(crashlytics);
  }

  Future<void> log(String name, [Map<String, Object>? parameters]) async {
    if (!analyticsAllowed) return;
    await analytics.logEvent(name, parameters);
  }

  void _installCrashHook(bool enabled) {
    if (enabled) {
      _previousFlutterError ??= FlutterError.onError;
      FlutterError.onError = (details) {
        _previousFlutterError?.call(details);
        crashes.recordError(
          details.exception,
          details.stack ?? StackTrace.empty,
        );
      };
      return;
    }
    if (_previousFlutterError != null) {
      FlutterError.onError = _previousFlutterError;
    }
  }
}

/// 沒有決定過、或帳號還沒登入時，兩個開關都是關的。
Future<void> applyInitialTelemetry({
  required Telemetry telemetry,
  required bool consentDecided,
  required bool analyticsConsent,
  required bool crashlyticsConsent,
}) {
  final allow = consentDecided;
  return telemetry.apply(
    analytics: allow && analyticsConsent,
    crashlytics: allow && crashlyticsConsent,
  );
}
