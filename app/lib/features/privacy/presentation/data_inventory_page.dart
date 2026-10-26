import 'package:flutter/material.dart';
import 'package:group_trip/core/widgets/form_widgets.dart';
import 'package:group_trip/l10n/app_strings.dart';

class DataInventoryPage extends StatelessWidget {
  const DataInventoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      AppStrings.inventoryBirthday,
      AppStrings.inventoryIdentity,
      AppStrings.inventoryLogin,
      AppStrings.inventoryTrip,
      AppStrings.inventoryLocation,
      AppStrings.inventoryFcm,
      AppStrings.inventoryTelemetry,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.inventoryTitle)),
      body: FormColumn(
        children: [
          const PageHeading(AppStrings.inventoryTitle),
          Text(
            AppStrings.inventoryIntro,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          for (final item in items)
            Text(item, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
