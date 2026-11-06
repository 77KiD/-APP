import 'package:flutter/material.dart';
import 'package:group_trip/app/app_scope.dart';
import 'package:group_trip/core/firebase/firebase_config.dart';
import 'package:group_trip/core/theme/semantic_colors.dart';
import 'package:group_trip/core/theme/spacing.dart';
import 'package:group_trip/core/widgets/app_shell.dart';
import 'package:group_trip/core/widgets/form_widgets.dart';
import 'package:group_trip/features/home/domain/decision_board.dart';
import 'package:group_trip/features/home/presentation/decision_board_view.dart';
import 'package:group_trip/features/settings/presentation/settings_page.dart';
import 'package:group_trip/features/trip/domain/invite_link.dart';
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
  DecisionBoard? _board;
  String? _error;
  int _loadSequence = 0;
  int _listSequence = 0;
  int _shareSequence = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reload();
      _openInviteFromLink();
    });
  }

  bool _handledInviteLink = false;

  /// 從邀請連結打開時，直接帶到加入頁並填好邀請碼（ADR 0012 第 3 點）。
  Future<void> _openInviteFromLink() async {
    final code = AppScope.of(context).initialInviteCode;
    if (code == null || _handledInviteLink) return;
    _handledInviteLink = true;
    await _open(JoinTripPage(initialCode: code));
  }

  Trip? get _selectedTrip {
    for (final trip in _trips) {
      if (trip.id == _selectedTripId) return trip;
    }
    return _trips.isEmpty ? null : _trips.first;
  }

  Future<void> _reload() async {
    final sequence = ++_listSequence;
    ++_loadSequence;
    final deps = AppScope.of(context);
    await deps.connectivity.refresh();
    if (!_isCurrentList(sequence)) return;
    try {
      final trips = await deps.trips.listMyTrips();
      if (!_isCurrentList(sequence)) return;
      setState(() {
        _trips = trips;
        _error = null;
        if (_board?.trip.id != _selectedTrip?.id) _board = null;
      });
    } on TripException catch (error) {
      if (!_isCurrentList(sequence)) return;
      setState(() => _error = error.message);
    }
    await _loadBoard();
  }

  bool _isCurrentList(int sequence) => mounted && sequence == _listSequence;

  bool _isCurrentLoad(int sequence, [String? tripId]) =>
      mounted &&
      sequence == _loadSequence &&
      (tripId == null || _selectedTrip?.id == tripId);

  /// 看板只讀現有資料：成員、修改申請、邀請碼。讀不到時不擋首頁。
  /// 成功回傳該次看板；失敗明確標記，已被新請求取代則不回傳可分享資料。
  Future<({DecisionBoard? board, bool failed, bool inviteFailed})> _loadBoard({
    bool forSharing = false,
  }) async {
    // 提示上的「重試」可能在首頁移除後才被按下。
    if (!mounted) return (board: null, failed: false, inviteFailed: false);
    final request = ++_loadSequence;
    final selected = _selectedTrip;
    if (selected == null) {
      setState(() => _board = null);
      return (board: null, failed: false, inviteFailed: false);
    }
    final deps = AppScope.of(context);
    try {
      // 分享前先更新連線狀態，不用畫面上留下的離線判斷讀舊資料。
      if (forSharing) {
        await deps.connectivity.refresh();
        if (!_isCurrentLoad(request, selected.id)) {
          return (board: null, failed: false, inviteFailed: false);
        }
      }
      // 重新讀旅程：公開邀請的截止時間、回程等可能在旅程頁被改過。
      final trip = await deps.trips.getTrip(selected.id);
      if (!_isCurrentLoad(request, selected.id)) {
        return (board: null, failed: false, inviteFailed: false);
      }
      if (trip.id != selected.id) {
        return (board: null, failed: true, inviteFailed: false);
      }
      final members = await deps.trips.listMembers(trip.id);
      final requests = await deps.trips.listRequests(trip.id);
      final validation = forSharing
          ? await deps.trips.revalidateInvites(trip.id)
          : (invites: await deps.trips.listInvites(trip.id), failed: false);
      final now = await deps.clock.now();
      final selfId = deps.auth.current?.id;
      TripMember? self;
      for (final member in members) {
        if (member.userId == selfId) self = member;
      }
      if (!_isCurrentLoad(request, selected.id)) {
        return (board: null, failed: false, inviteFailed: false);
      }
      final board = DecisionBoard.build(
        trip: trip,
        self: self,
        members: members,
        requests: requests,
        invites: validation.invites,
        now: now,
        inviteUrlFor: deps.firebaseConfigured
            ? (code) => InviteLink.build(
                projectId: FirebaseConfig.projectId,
                code: code,
              )
            : null,
      );
      // 重驗暫時失敗時保留畫面上的看板，不把它降級成「沒有可分享的碼」。
      if (!validation.failed) setState(() => _board = board);
      return (board: board, failed: false, inviteFailed: validation.failed);
    } on TripException {
      // 同一旅程的舊看板仍可閱讀，但絕不可當成這次重讀成功的結果。
      return (
        board: null,
        failed: _isCurrentLoad(request, selected.id),
        inviteFailed: false,
      );
    }
  }

  Future<void> _onBoardAction(BoardAction action) async {
    final board = _board;
    if (board == null) return;
    switch (action) {
      case BoardAction.openTrip:
        await _openTrip(board.trip);
      case BoardAction.shareInvite:
        final fresh = await _freshBoard(
          retry: () => _onBoardAction(action),
          requireInvite: true,
        );
        final invite = fresh?.shareableInvite;
        if (!mounted || fresh == null) return;
        if (invite == null) {
          // 載入後碼已過期或失效：不分享舊碼，提示到旅程頁重新產生。
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStrings.boardNoShareableInvite)),
          );
          return;
        }
        await AppScope.of(context).share
            .shareText(fresh.inviteShareText(invite));
    }
  }

  Future<void> _shareBoard() async {
    final fresh = await _freshBoard(retry: _shareBoard);
    if (!mounted || fresh == null) return;
    await AppScope.of(context).share.shareText(fresh.shareText());
  }

  /// 分享前用現在的時間與最新的旅程、邀請碼重算看板，不用畫面載入時的快照
  /// （Codex 審查 #60 F02）。
  Future<DecisionBoard?> _freshBoard({
    required VoidCallback retry,
    bool requireInvite = false,
  }) async {
    final share = ++_shareSequence;
    final tripId = _selectedTrip?.id;
    final result = await _loadBoard(forSharing: true);
    // 連按時只處理最後一次，較早的那次不提示。
    if (!mounted || share != _shareSequence) return null;
    // 被同一趟旅程的背景載入取代時沒有可分享的資料；要告訴使用者，不能無聲取消。
    // 使用者已切到別的旅程時，原本的分享就此取消，不提示。
    final superseded =
        result.board == null &&
        !result.failed &&
        tripId != null &&
        _selectedTrip?.id == tripId;
    if (result.failed ||
        superseded ||
        (requireInvite &&
            result.inviteFailed &&
            result.board?.shareableInvite == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(AppStrings.boardRefreshFailed),
          action: SnackBarAction(
            label: AppStrings.boardRetry,
            // 重試只針對原本的旅程，不能變成分享現在選到的另一趟。
            onPressed: () {
              if (mounted && _selectedTrip?.id == tripId) retry();
            },
          ),
        ),
      );
      return null;
    }
    return result.board;
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
      // 在行程、成員分頁改過資料後回首頁，看板要跟著更新（Codex 審查 #60 F03）。
      onTabChanged: (tab) {
        if (tab == BottomNavTab.home) _reload();
      },
      bodyBuilder: (context, tab) {
        switch (tab) {
          case BottomNavTab.home:
            return _HomeTab(
              name: deps.auth.current?.displayName ?? '',
              localMode: !deps.firebaseConfigured,
              isWeb: deps.isWeb,
              trips: _trips,
              error: _error,
              board: _board,
              onBoardAction: _onBoardAction,
              onShareBoard: _shareBoard,
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
            if (deps.isWeb) {
              return const _ComingSoon(message: AppStrings.webFindInApp);
            }
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
    required this.isWeb,
    required this.trips,
    required this.error,
    required this.board,
    required this.onBoardAction,
    required this.onShareBoard,
    required this.onOpenTrip,
    required this.onCreate,
    required this.onJoin,
  });

  final String name;
  final bool localMode;

  /// 網頁版不能建立旅程，只能加入（ADR 0012 第 2 點）。
  final bool isWeb;
  final List<Trip> trips;
  final String? error;
  final DecisionBoard? board;
  final ValueChanged<BoardAction> onBoardAction;
  final VoidCallback onShareBoard;
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
        if (board != null) ...[
          const SizedBox(height: AppSpacing.s2),
          DecisionBoardView(
            board: board!,
            onAction: onBoardAction,
            onShareBoard: onShareBoard,
          ),
        ],
        FormErrorText(error),
        const SizedBox(height: AppSpacing.s2),
        if (isWeb) ...[
          Text(
            AppStrings.webCreateInApp,
            style: textTheme.bodyMedium?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: AppSpacing.s2),
          FilledButton(
            onPressed: onJoin,
            child: const Text(AppStrings.joinTrip),
          ),
        ] else ...[
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
