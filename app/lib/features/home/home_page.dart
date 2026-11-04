import 'package:flutter/material.dart';
import 'package:group_trip/app/app_scope.dart';
import 'package:group_trip/core/widgets/form_widgets.dart';
import 'package:group_trip/features/consent/presentation/consent_page.dart';
import 'package:group_trip/features/location_disclosure/presentation/location_disclosure_page.dart';
import 'package:group_trip/features/privacy/presentation/data_inventory_page.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/presentation/create_trip_page.dart';
import 'package:group_trip/features/trip/presentation/join_trip_page.dart';
import 'package:group_trip/features/trip/presentation/trip_detail_page.dart';
import 'package:group_trip/l10n/app_strings.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Trip> _trips = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  Future<void> _reload() async {
    final deps = AppScope.of(context);
    await deps.connectivity.refresh();
    try {
      final trips = await deps.trips.listMyTrips();
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _error = null;
      });
    } on TripException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  Future<void> _openCreate() async {
    final deps = AppScope.of(context);
    final zone = await deps.timeZone.localIana();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CreateTripPage(initialTimeZone: zone)),
    );
    await _reload();
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    await _reload();
  }

  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    await AppScope.of(context).auth.signOut();
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    final name = deps.auth.current?.displayName ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.myTrips)),
      body: FormColumn(
        children: [
          PageHeading(name.isEmpty ? AppStrings.myTrips : name),
          if (!deps.firebaseConfigured) const Text(AppStrings.firebaseDevBanner),
          if (_trips.isEmpty) const Text(AppStrings.emptyTrips),
          for (final trip in _trips)
            OutlinedButton(
              onPressed: () => _open(TripDetailPage(tripId: trip.id)),
              child: Text('${trip.title}，${trip.startDate}'),
            ),
          FormErrorText(_error),
          FilledButton(
            onPressed: _openCreate,
            child: const Text(AppStrings.createTrip),
          ),
          OutlinedButton(
            onPressed: () => _open(const JoinTripPage()),
            child: const Text(AppStrings.joinTrip),
          ),
          OutlinedButton(
            onPressed: () => _open(const LocationDisclosurePage()),
            child: const Text(AppStrings.locationDisclosureEntry),
          ),
          OutlinedButton(
            onPressed: () => _open(const DataInventoryPage()),
            child: const Text(AppStrings.dataInventoryEntry),
          ),
          OutlinedButton(
            onPressed: () => _open(const ConsentPage()),
            child: const Text(AppStrings.telemetrySettings),
          ),
          TextButton(onPressed: _signOut, child: const Text(AppStrings.signOut)),
        ],
      ),
    );
  }
}
