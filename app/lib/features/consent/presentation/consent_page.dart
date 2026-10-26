import 'package:flutter/material.dart';
import 'package:group_trip/app/app_scope.dart';
import 'package:group_trip/core/telemetry/telemetry.dart';
import 'package:group_trip/core/widgets/form_widgets.dart';
import 'package:group_trip/l10n/app_strings.dart';

class ConsentPage extends StatefulWidget {
  const ConsentPage({super.key});

  @override
  State<ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<ConsentPage> {
  bool _analytics = false;
  bool _crashlytics = false;
  bool _ready = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    final account = AppScope.of(context).auth.current;
    _analytics = account?.analyticsConsent ?? false;
    _crashlytics = account?.crashlyticsConsent ?? false;
    _ready = true;
  }

  Future<void> _save({required bool useSwitches}) async {
    setState(() => _busy = true);
    final deps = AppScope.of(context);
    final analytics = useSwitches && _analytics;
    final crashlytics = useSwitches && _crashlytics;
    final updated = await deps.auth.updateConsent(
      analytics: analytics,
      crashlytics: crashlytics,
    );
    await applyInitialTelemetry(
      telemetry: deps.telemetry,
      consentDecided: updated.consentDecided,
      analyticsConsent: updated.analyticsConsent,
      crashlyticsConsent: updated.crashlyticsConsent,
    );
    if (!mounted) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FormColumn(
        children: [
          const PageHeading(AppStrings.consentTitle),
          Text(
            AppStrings.consentBody,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _analytics,
            onChanged: _busy ? null : (value) => setState(() => _analytics = value),
            title: const Text(AppStrings.analyticsSwitch),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _crashlytics,
            onChanged: _busy
                ? null
                : (value) => setState(() => _crashlytics = value),
            title: const Text(AppStrings.crashSwitch),
          ),
          FilledButton(
            onPressed: _busy ? null : () => _save(useSwitches: true),
            child: const Text(AppStrings.consentSave),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _save(useSwitches: false),
            child: const Text(AppStrings.consentDecline),
          ),
        ],
      ),
    );
  }
}
