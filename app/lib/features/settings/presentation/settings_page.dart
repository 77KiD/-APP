import 'package:flutter/material.dart';
import 'package:group_trip/app/app_scope.dart';
import 'package:group_trip/core/widgets/form_widgets.dart';
import 'package:group_trip/features/consent/presentation/consent_page.dart';
import 'package:group_trip/features/location_disclosure/presentation/location_disclosure_page.dart';
import 'package:group_trip/features/privacy/presentation/data_inventory_page.dart';
import 'package:group_trip/l10n/app_strings.dart';

/// 從頂部頭像進入。隱私、分析與登出原本混在首頁的旅程按鈕之間，
/// 移到這裡讓首頁只放旅程（概念 UI 缺點分析第 1 點）。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _open(BuildContext context, Widget page) {
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _signOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    await AppScope.of(context).auth.signOut();
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final name = AppScope.of(context).auth.current?.displayName ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.settingsTitle)),
      body: FormColumn(
        children: [
          PageHeading(name.isEmpty ? AppStrings.settingsTitle : name),
          OutlinedButton(
            onPressed: () => _open(context, const LocationDisclosurePage()),
            child: const Text(AppStrings.locationDisclosureEntry),
          ),
          OutlinedButton(
            onPressed: () => _open(context, const DataInventoryPage()),
            child: const Text(AppStrings.dataInventoryEntry),
          ),
          OutlinedButton(
            onPressed: () => _open(context, const ConsentPage()),
            child: const Text(AppStrings.telemetrySettings),
          ),
          TextButton(
            onPressed: () => _signOut(context),
            child: const Text(AppStrings.signOut),
          ),
        ],
      ),
    );
  }
}
