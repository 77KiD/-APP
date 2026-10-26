import 'package:flutter/material.dart';
import 'package:group_trip/app/app_scope.dart';
import 'package:group_trip/core/widgets/form_widgets.dart';
import 'package:group_trip/l10n/app_strings.dart';

/// 說明畫面只記下「已閱讀」。系統權限視窗要等之後的「發送定位」，而且必須先經過
/// [LocationPermissionGateway]。
class LocationDisclosurePage extends StatefulWidget {
  const LocationDisclosurePage({super.key});

  @override
  State<LocationDisclosurePage> createState() => _LocationDisclosurePageState();
}

class _LocationDisclosurePageState extends State<LocationDisclosurePage> {
  String? _message;
  bool _busy = false;

  Future<void> _acknowledge() async {
    final deps = AppScope.of(context);
    final account = deps.auth.current;
    if (account == null) return;
    setState(() => _busy = true);
    await deps.disclosure.acknowledge(account.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = AppStrings.disclosureSaved;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.disclosureTitle)),
      body: FormColumn(
        children: [
          const PageHeading(AppStrings.disclosureTitle),
          Text(
            AppStrings.disclosureBody,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          FilledButton(
            onPressed: _busy ? null : _acknowledge,
            child: const Text(AppStrings.disclosureAck),
          ),
          if (_message != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _message!,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
        ],
      ),
    );
  }
}
