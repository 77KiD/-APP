import 'package:flutter/material.dart';
import 'package:group_trip/app/app_scope.dart';
import 'package:group_trip/core/theme/semantic_colors.dart';
import 'package:group_trip/core/theme/spacing.dart';
import 'package:group_trip/core/widgets/app_shell.dart';
import 'package:group_trip/core/widgets/form_widgets.dart';
import 'package:group_trip/features/settings/presentation/settings_page.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/presentation/create_trip_page.dart';
import 'package:group_trip/features/trip/presentation/join_trip_page.dart';
import 'package:group_trip/features/trip/presentation/trip_detail_page.dart';
import 'package:group_trip/l10n/app_strings.dart';

/// 登入後的主畫面：原型的底部導覽（行程、找人、首頁、成員），不含聊天（ADR 0011）。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Trip> _trips = [];
  String? _selectedTripId;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  Trip? get _selectedTrip {
    for (final trip in _trips) {
      if (trip.id == _selectedTripId) return trip;
    }
    return _trips.isEmpty ? null : _trips.first;
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
    await _open(CreateTripPage(initialTimeZone: zone));
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    await _reload();
  }

  Future<void> _openTrip(Trip trip) async {
    setState(() => _selectedTripId = trip.id);
    await _open(TripDetailPage(tripId: trip.id));
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    final selected = _selectedTrip;
    return AppShell(
      currentTrip: selected?.title,
      connectionStatus: deps.connectivity.isOnline
          ? ConnectionStatus.online
          : ConnectionStatus.offline,
      onSettingsTap: () => _open(const SettingsPage()),
      bodyBuilder: (context, tab) {
        switch (tab) {
          case BottomNavTab.home:
            return _HomeTab(
              name: deps.auth.current?.displayName ?? '',
              localMode: !deps.firebaseConfigured,
              trips: _trips,
              error: _error,
              onOpenTrip: _openTrip,
              onCreate: _openCreate,
              onJoin: () => _open(const JoinTripPage()),
            );
          case BottomNavTab.itinerary:
          case BottomNavTab.members:
            // 第 1 階段先把旅程頁放進分頁；之後的階段再拆成行程與成員。
            if (selected == null) return null;
            return TripDetailPage(
              key: ValueKey('${tab.name}-${selected.id}'),
              tripId: selected.id,
              embedded: true,
            );
          case BottomNavTab.find:
            if (selected == null) return null;
            return const _ComingSoon(message: AppStrings.findComingSoon);
        }
      },
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.name,
    required this.localMode,
    required this.trips,
    required this.error,
    required this.onOpenTrip,
    required this.onCreate,
    required this.onJoin,
  });

  final String name;
  final bool localMode;
  final List<Trip> trips;
  final String? error;
  final ValueChanged<Trip> onOpenTrip;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s2,
        AppSpacing.s4,
        AppSpacing.s6,
      ),
      children: [
        Text(
          name.isEmpty ? AppStrings.myTrips : AppStrings.greeting(name),
          style: textTheme.headlineSmall?.copyWith(color: colors.text),
        ),
        const SizedBox(height: AppSpacing.s3),
        if (localMode) ...[
          Text(
            AppStrings.firebaseDevBanner,
            style: textTheme.bodyMedium?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: AppSpacing.s3),
        ],
        if (trips.isEmpty)
          Text(
            AppStrings.emptyTrips,
            style: textTheme.bodyLarge?.copyWith(color: colors.muted),
          ),
        for (final trip in trips) ...[
          _TripCard(trip: trip, onTap: () => onOpenTrip(trip)),
          const SizedBox(height: AppSpacing.s3),
        ],
        FormErrorText(error),
        const SizedBox(height: AppSpacing.s2),
        FilledButton(
          onPressed: onCreate,
          child: const Text(AppStrings.createTrip),
        ),
        const SizedBox(height: AppSpacing.s2),
        OutlinedButton(
          onPressed: onJoin,
          child: const Text(AppStrings.joinTrip),
        ),
      ],
    );
  }
}

/// 原型的 `--tripcard`：主色到強調色的淡漸層疊在 surface 上，圓角 18。
class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.onTap});

  final Trip trip;
  final VoidCallback onTap;

  String get _status => switch (trip.status) {
    TripStatus.planning => AppStrings.statusPlanning,
    TripStatus.active => AppStrings.statusActive,
    TripStatus.ended => AppStrings.statusEnded,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadii.card);
    return Semantics(
      button: true,
      label: '${trip.title}，$_status，${trip.startDate} 到 ${trip.endDate}',
      excludeSemantics: true,
      child: Material(
        color: colors.surface,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: colors.line),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0, 0.7],
                colors: [
                  colors.primary.withValues(alpha: 0.28),
                  colors.accent.withValues(alpha: 0.10),
                ],
              ),
            ),
            padding: const EdgeInsets.all(AppSpacing.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        trip.title,
                        style: textTheme.titleLarge?.copyWith(
                          color: colors.text,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s2,
                        vertical: AppSpacing.s1,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(AppRadii.tag),
                        border: Border.all(color: colors.line),
                      ),
                      child: Text(
                        _status,
                        style: textTheme.labelMedium?.copyWith(
                          color: colors.text,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s1),
                Text(
                  AppStrings.tripDates(trip.startDate, trip.endDate),
                  style: textTheme.bodyMedium?.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s5),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: colors.muted),
        ),
      ),
    );
  }
}
