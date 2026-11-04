import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/l10n/app_strings.dart';

/// 首頁的決定看板（ADR 0011 第 2 點、改版路線圖第 2 階段）。
enum BoardSection {
  decided,
  pending,
  todo;

  String get label => switch (this) {
    BoardSection.decided => AppStrings.boardDecided,
    BoardSection.pending => AppStrings.boardPending,
    BoardSection.todo => AppStrings.boardTodo,
  };
}

/// 點看板項目時要做的事。
enum BoardAction {
  /// 打開旅程頁（審核申請、設定回程、指定副隊長、同步邀請碼都在那裡）。
  openTrip,

  /// 用系統分享選單送出邀請碼。
  shareInvite,
}

class BoardItem {
  const BoardItem({
    required this.section,
    required this.title,
    this.detail,
    this.action,
  });

  final BoardSection section;
  final String title;
  final String? detail;
  final BoardAction? action;
}

class DecisionBoard {
  const DecisionBoard({
    required this.trip,
    required this.order,
    required this.items,
    this.shareableInvite,
  });

  final Trip trip;

  /// 依旅程階段排好的區塊順序。空的區塊不顯示。
  final List<BoardSection> order;
  final List<BoardItem> items;

  /// 伺服器已確認、還在效期內、可以分享的邀請碼。
  final InviteRecord? shareableInvite;

  List<BoardItem> section(BoardSection section) => [
    for (final item in items)
      if (item.section == section) item,
  ];

  /// 概念 UI 缺點分析第 2 點：同一個首頁，依階段調整資訊順序，不做四套介面。
  static List<BoardSection> orderFor(TripStatus status) => switch (status) {
    TripStatus.planning => const [
      BoardSection.todo,
      BoardSection.pending,
      BoardSection.decided,
    ],
    TripStatus.active => const [
      BoardSection.todo,
      BoardSection.decided,
      BoardSection.pending,
    ],
    TripStatus.ended => const [BoardSection.decided],
  };

  static DecisionBoard build({
    required Trip trip,
    required TripMember? self,
    required List<TripMember> members,
    required List<ModificationRequest> requests,
    required List<InviteRecord> invites,
    required DateTime now,
  }) {
    final items = <BoardItem>[];
    final role = self?.role ?? MemberRole.member;
    final manager = role.canEditExpectedReturnDirectly;

    // 已決定
    items.add(
      BoardItem(
        section: BoardSection.decided,
        title: AppStrings.boardDates,
        detail:
            '${AppStrings.tripDates(trip.startDate, trip.endDate)}（${trip.timeZone}）',
      ),
    );
    if (trip.expectedReturnAt != null) {
      items.add(
        BoardItem(
          section: BoardSection.decided,
          title: AppStrings.expectedReturn,
          detail: TripTime.format(trip.expectedReturnAt!, trip.timeZone),
        ),
      );
    }
    items.add(
      BoardItem(
        section: BoardSection.decided,
        title: AppStrings.boardMembers,
        detail: AppStrings.boardMemberCount(members.length),
      ),
    );

    // 待決定
    final open = [
      for (final request in requests)
        if (request.status == RequestStatus.pending &&
            (request.expiresAt == null || now.isBefore(request.expiresAt!)))
          request,
    ];
    if (trip.expectedReturnAt == null) {
      items.add(
        const BoardItem(
          section: BoardSection.pending,
          title: AppStrings.expectedReturn,
          detail: AppStrings.boardUndecided,
        ),
      );
    }
    if (open.isNotEmpty) {
      items.add(
        BoardItem(
          section: BoardSection.pending,
          title: AppStrings.boardRequests,
          detail: AppStrings.boardRequestCount(open.length),
          action: BoardAction.openTrip,
        ),
      );
    }

    // 我的待辦：只列「我」現在要做的少數事項（缺點分析第 3 點）。
    final shareable = shareableInviteFor(trip: trip, invites: invites, now: now);
    if (trip.status != TripStatus.ended) {
      if (manager && open.isNotEmpty) {
        items.add(
          BoardItem(
            section: BoardSection.todo,
            title: AppStrings.boardReviewRequests(open.length),
            action: BoardAction.openTrip,
          ),
        );
      }
      if (role == MemberRole.captain &&
          TripPolicy.viceCaptainRequiredToStart(members.length) &&
          !members.any((member) => member.role == MemberRole.viceCaptain)) {
        items.add(
          const BoardItem(
            section: BoardSection.todo,
            title: AppStrings.boardAssignVice,
            detail: AppStrings.viceRequired,
            action: BoardAction.openTrip,
          ),
        );
      }
      if (manager && trip.expectedReturnAt == null) {
        items.add(
          const BoardItem(
            section: BoardSection.todo,
            title: AppStrings.boardSetReturn,
            action: BoardAction.openTrip,
          ),
        );
      }
      if (invites.any((invite) => !invite.serverConfirmed)) {
        items.add(
          const BoardItem(
            section: BoardSection.todo,
            title: AppStrings.boardSyncInvites,
            detail: AppStrings.invitePending,
            action: BoardAction.openTrip,
          ),
        );
      }
      if (members.length < 2) {
        items.add(
          BoardItem(
            section: BoardSection.todo,
            title: AppStrings.boardInviteFriends,
            detail: shareable == null
                ? AppStrings.boardNoShareableInvite
                : AppStrings.boardShareInviteHint,
            action: shareable == null
                ? BoardAction.openTrip
                : BoardAction.shareInvite,
          ),
        );
      }
    }

    return DecisionBoard(
      trip: trip,
      order: orderFor(trip.status),
      items: items,
      shareableInvite: shareable,
    );
  }

  /// 可以分享的邀請碼：伺服器已確認、啟用中、在效期內，而且沒有被關閉公開邀請
  /// 的截止時間擋下（一般成員在 `invitesResetAt` 之前產生的碼，見 0007、#53）。
  /// Codex 審查 #60 F01。
  static InviteRecord? shareableInviteFor({
    required Trip trip,
    required List<InviteRecord> invites,
    required DateTime now,
  }) {
    InviteRecord? best;
    for (final invite in invites) {
      if (!invite.serverConfirmed || !invite.active) continue;
      if (TripPolicy.memberInviteBlocked(
        invitesResetAt: trip.invitesResetAt,
        issuerRole: invite.issuerRole,
        createdAt: invite.createdAt,
      )) {
        continue;
      }
      if (TripPolicy.isInviteJoinExpired(
        expiresAt: invite.expiresAt,
        createdAt: invite.createdAt,
        now: now,
      )) {
        continue;
      }
      if (best == null || invite.expiresAt.isAfter(best.expiresAt)) {
        best = invite;
      }
    }
    return best;
  }

  /// 給 LINE 群組看的文字：要能獨立閱讀，因為很多人只會在 LINE 看到它。
  String shareText() {
    final buffer = StringBuffer(AppStrings.boardShareTitle(trip.title));
    for (final section in order) {
      final entries = this.section(section);
      if (entries.isEmpty) continue;
      buffer
        ..writeln()
        ..writeln()
        ..write('【${section.label}】');
      for (final item in entries) {
        buffer
          ..writeln()
          ..write('・${item.title}');
        if (item.detail != null) buffer.write('：${item.detail}');
      }
    }
    final invite = shareableInvite;
    if (invite != null) {
      buffer
        ..writeln()
        ..writeln()
        ..write(AppStrings.boardShareInviteLine(invite.code));
    }
    return buffer.toString();
  }

  /// 只分享邀請碼時的文字。
  static String inviteShareText(Trip trip, InviteRecord invite) =>
      AppStrings.inviteShareText(trip.title, invite.code);
}
