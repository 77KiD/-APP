import 'package:flutter/material.dart';
import 'package:group_trip/core/theme/semantic_colors.dart';
import 'package:group_trip/core/theme/spacing.dart';

enum BottomNavTab {
  itinerary,
  find,
  home,
  chat,
  members;

  String get label {
    switch (this) {
      case BottomNavTab.itinerary:
        return '行程';
      case BottomNavTab.find:
        return '找人';
      case BottomNavTab.home:
        return '首頁';
      case BottomNavTab.chat:
        return '聊天';
      case BottomNavTab.members:
        return '成員';
    }
  }

  IconData get icon {
    switch (this) {
      case BottomNavTab.itinerary:
        return Icons.route_outlined;
      case BottomNavTab.find:
        return Icons.explore_outlined;
      case BottomNavTab.home:
        return Icons.home_outlined;
      case BottomNavTab.chat:
        return Icons.chat_bubble_outline;
      case BottomNavTab.members:
        return Icons.people_outline;
    }
  }

  IconData get selectedIcon {
    switch (this) {
      case BottomNavTab.itinerary:
        return Icons.route;
      case BottomNavTab.find:
        return Icons.explore;
      case BottomNavTab.home:
        return Icons.home;
      case BottomNavTab.chat:
        return Icons.chat_bubble;
      case BottomNavTab.members:
        return Icons.people;
    }
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.currentTrip,
    this.onSettingsTap,
    this.hideBottomNav = false,
    this.chatUnreadCount = 0,
    this.pendingApprovalsCount = 0,
    this.isLeaderOrDeputy = false,
  });

  final String? currentTrip;
  final VoidCallback? onSettingsTap;
  final bool hideBottomNav;
  final int chatUnreadCount;
  final int pendingApprovalsCount;
  final bool isLeaderOrDeputy;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  BottomNavTab _currentTab = BottomNavTab.home;
  final ConnectionStatus _connectionStatus = ConnectionStatus.online;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          _AppHeader(
            currentTab: _currentTab,
            currentTrip: widget.currentTrip,
            connectionStatus: _connectionStatus,
            onSettingsTap: widget.onSettingsTap,
          ),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
      bottomNavigationBar: widget.hideBottomNav
          ? null
          : _AppBottomNav(
              currentTab: _currentTab,
              onTabChanged: (tab) => setState(() => _currentTab = tab),
              chatUnreadCount: widget.chatUnreadCount,
              pendingApprovalsCount: widget.pendingApprovalsCount,
              showApprovalsCount: widget.isLeaderOrDeputy,
            ),
    );
  }

  Widget _buildBody() {
    switch (_currentTab) {
      case BottomNavTab.itinerary:
        return _EmptyStateBody(
          icon: Icons.route_outlined,
          title: '行程規劃',
          message: widget.currentTrip == null ? '建立或加入旅程後，就能在這裡規劃行程' : '行程頁面開發中',
        );
      case BottomNavTab.find:
        return _EmptyStateBody(
          icon: Icons.explore_outlined,
          title: '找人',
          message: widget.currentTrip == null ? '建立或加入旅程後，就能在地圖上看到夥伴的位置' : '找人地圖開發中',
        );
      case BottomNavTab.home:
        return _EmptyStateBody(
          icon: Icons.home_outlined,
          title: '首頁',
          message: '首頁內容開發中',
        );
      case BottomNavTab.chat:
        return _EmptyStateBody(
          icon: Icons.chat_bubble_outline,
          title: '聊天',
          message: widget.currentTrip == null ? '建立或加入旅程後，就能和夥伴聊天' : '聊天功能開發中',
        );
      case BottomNavTab.members:
        return _EmptyStateBody(
          icon: Icons.people_outline,
          title: '成員',
          message: widget.currentTrip == null ? '建立或加入旅程後，就能查看所有成員' : '成員頁面開發中',
        );
    }
  }
}

class _AppHeader extends StatelessWidget {
  const _AppHeader({
    required this.currentTab,
    required this.currentTrip,
    required this.connectionStatus,
    this.onSettingsTap,
  });

  final BottomNavTab currentTab;
  final String? currentTrip;
  final ConnectionStatus connectionStatus;
  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasTrip = currentTrip != null && currentTrip!.isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s4,
        MediaQuery.of(context).padding.top + AppSpacing.s2,
        AppSpacing.s4,
        AppSpacing.s3,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.bg.withValues(alpha: 0.96),
            colors.bg.withValues(alpha: 0),
          ],
          stops: const [0.75, 1.0],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _getTitle(),
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.text,
                      ),
                  semanticsLabel: _getTitle(),
                ),
                if (hasTrip)
                  Text(
                    currentTrip!,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: colors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                  )
                else if (_needsTripMessage())
                  Text(
                    _getExplanation(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: colors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.s3),
          _ConnectionIndicator(status: connectionStatus),
          SizedBox(width: AppSpacing.s2),
          _AvatarButton(onTap: onSettingsTap),
        ],
      ),
    );
  }

  String _getTitle() {
    switch (currentTab) {
      case BottomNavTab.itinerary:
        return '行程';
      case BottomNavTab.find:
        return '找人';
      case BottomNavTab.home:
        return '首頁';
      case BottomNavTab.chat:
        return '聊天';
      case BottomNavTab.members:
        return '成員';
    }
  }

  bool _needsTripMessage() {
    return currentTab != BottomNavTab.home && (currentTrip == null || currentTrip!.isEmpty);
  }

  String _getExplanation() {
    switch (currentTab) {
      case BottomNavTab.itinerary:
        return '建立或加入旅程後可用';
      case BottomNavTab.find:
        return '建立或加入旅程後可用';
      case BottomNavTab.chat:
        return '建立或加入旅程後可用';
      case BottomNavTab.members:
        return '建立或加入旅程後可用';
      case BottomNavTab.home:
        return '';
    }
  }
}

enum ConnectionStatus { online, offline, syncing }

class _ConnectionIndicator extends StatelessWidget {
  const _ConnectionIndicator({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (label, dotColor) = switch (status) {
      ConnectionStatus.online => ('線上', colors.green),
      ConnectionStatus.offline => ('離線', colors.dim),
      ConnectionStatus.syncing => ('同步中', colors.amber),
    };

    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: status == ConnectionStatus.offline ? colors.muted : colors.text,
                ),
          ),
        ],
      ),
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      label: '設定',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colors.primary,
            shape: BoxShape.circle,
          ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  '我',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colors.onAccent,
                      ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.line, width: 1.5),
                  ),
                  child: Icon(
                    Icons.settings,
                    size: 12,
                    color: colors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppBottomNav extends StatelessWidget {
  const _AppBottomNav({
    required this.currentTab,
    required this.onTabChanged,
    this.chatUnreadCount = 0,
    this.pendingApprovalsCount = 0,
    this.showApprovalsCount = false,
  });

  final BottomNavTab currentTab;
  final ValueChanged<BottomNavTab> onTabChanged;
  final int chatUnreadCount;
  final int pendingApprovalsCount;
  final bool showApprovalsCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: colors.bg.withValues(alpha: 0.97),
        border: Border(top: BorderSide(color: colors.line)),
      ),
      padding: EdgeInsets.fromLTRB(6, 6, 6, bottomPadding + 22),
      child: Row(
        children: [
          for (final tab in BottomNavTab.values)
            Expanded(
              child: _NavButton(
                tab: tab,
                isSelected: currentTab == tab,
                onTap: () => onTabChanged(tab),
                badgeCount: tab == BottomNavTab.chat
                    ? chatUnreadCount
                    : (tab == BottomNavTab.members && showApprovalsCount
                        ? pendingApprovalsCount
                        : 0),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.tab,
    required this.isSelected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final BottomNavTab tab;
  final bool isSelected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isHome = tab == BottomNavTab.home;

    String semanticsLabel = tab.label;
    if (badgeCount > 0) {
      if (tab == BottomNavTab.chat) {
        semanticsLabel = '$semanticsLabel，$badgeCount 則未讀訊息';
      } else if (tab == BottomNavTab.members) {
        semanticsLabel = '$semanticsLabel，$badgeCount 則待審核';
      }
    }

    Widget button = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isHome)
          Transform.translate(
            offset: const Offset(0, -28),
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: colors.bg, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                isSelected ? tab.selectedIcon : tab.icon,
                size: 26,
                color: colors.onAccent,
              ),
            ),
          )
        else ...[
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                isSelected ? tab.selectedIcon : tab.icon,
                size: 24,
                color: isSelected ? colors.primaryInk : colors.dim,
              ),
              if (badgeCount > 0)
                Positioned(
                  top: -6,
                  right: -12,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        badgeCount > 99 ? '99+' : badgeCount.toString(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: colors.onAccent,
                              height: 1,
                            ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 2),
          Text(
            tab.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isSelected ? colors.primaryInk : colors.dim,
                ),
          ),
        ],
      ],
    );

    if (isSelected && !isHome) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 2,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 44,
                height: 30,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
          button,
        ],
      );
    }

    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticsLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.button),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: button,
        ),
      ),
    );
  }
}

class _EmptyStateBody extends StatelessWidget {
  const _EmptyStateBody({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                icon,
                size: 34,
                color: colors.primaryInk,
              ),
            ),
            SizedBox(height: AppSpacing.s4),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: colors.text,
                  ),
            ),
            SizedBox(height: 6),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.muted,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
