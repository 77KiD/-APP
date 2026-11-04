import 'package:flutter_test/flutter_test.dart';
import 'package:group_trip/features/home/domain/decision_board.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/l10n/app_strings.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  final now = DateTime.utc(2026, 10, 26, 1);

  Trip trip({
    TripStatus status = TripStatus.planning,
    DateTime? expectedReturnAt,
  }) {
    return Trip(
      id: 't1',
      title: '京都自由行',
      captainId: 'cap',
      startDate: '2026-11-01',
      endDate: '2026-11-05',
      timeZone: 'Asia/Taipei',
      expectedReturnAt: expectedReturnAt,
      inviteCode: 'CODE0001',
      status: status,
      memberIds: const ['cap'],
      createdAt: now,
      updatedAt: now,
    );
  }

  TripMember member(String id, MemberRole role) => TripMember(
    tripId: 't1',
    userId: id,
    displayName: id,
    role: role,
    isMinor: false,
    joinedAt: now,
  );

  InviteRecord invite({
    bool confirmed = true,
    DateTime? createdAt,
    String code = 'CODE0001',
  }) {
    final created = createdAt ?? now.subtract(const Duration(minutes: 5));
    return InviteRecord(
      code: code,
      tripId: 't1',
      createdBy: 'cap',
      createdAt: created,
      expiresAt: created.add(const Duration(hours: 1)),
      serverConfirmed: confirmed,
    );
  }

  ModificationRequest request() => ModificationRequest(
    id: 'r1',
    tripId: 't1',
    requesterId: 'm1',
    requesterName: 'm1',
    type: ModificationType.expectedReturnTime,
    proposedExpectedReturnAt: DateTime.utc(2026, 11, 5, 10),
    status: RequestStatus.pending,
    createdAt: now,
    expiresAt: now.add(const Duration(minutes: 30)),
  );

  Iterable<String> titles(DecisionBoard board, BoardSection section) =>
      board.section(section).map((item) => item.title);

  test('規劃中的隊長獨自一人：待辦排最前，提示設定回程與邀請朋友', () {
    final captain = member('cap', MemberRole.captain);
    final board = DecisionBoard.build(
      trip: trip(),
      self: captain,
      members: [captain],
      requests: const [],
      invites: [invite()],
      now: now,
    );

    expect(board.order, [
      BoardSection.todo,
      BoardSection.pending,
      BoardSection.decided,
    ]);
    expect(
      titles(board, BoardSection.todo),
      containsAll([AppStrings.boardSetReturn, AppStrings.boardInviteFriends]),
    );
    final inviteItem = board
        .section(BoardSection.todo)
        .firstWhere((item) => item.title == AppStrings.boardInviteFriends);
    expect(inviteItem.action, BoardAction.shareInvite);
    expect(board.shareableInvite?.code, 'CODE0001');
    expect(titles(board, BoardSection.pending), [AppStrings.expectedReturn]);
    expect(
      titles(board, BoardSection.decided),
      containsAll([AppStrings.boardDates, AppStrings.boardMembers]),
    );
  });

  test('尚未同步的邀請碼不能分享，待辦改成同步邀請碼', () {
    final captain = member('cap', MemberRole.captain);
    final board = DecisionBoard.build(
      trip: trip(),
      self: captain,
      members: [captain],
      requests: const [],
      invites: [invite(confirmed: false)],
      now: now,
    );

    expect(board.shareableInvite, isNull);
    expect(
      titles(board, BoardSection.todo),
      contains(AppStrings.boardSyncInvites),
    );
    final inviteItem = board
        .section(BoardSection.todo)
        .firstWhere((item) => item.title == AppStrings.boardInviteFriends);
    expect(inviteItem.action, BoardAction.openTrip);
    expect(board.shareText(), isNot(contains('CODE0001')));
  });

  test('過期的邀請碼不會被分享', () {
    final captain = member('cap', MemberRole.captain);
    final board = DecisionBoard.build(
      trip: trip(),
      self: captain,
      members: [captain],
      requests: const [],
      invites: [invite(createdAt: now.subtract(const Duration(hours: 2)))],
      now: now,
    );

    expect(board.shareableInvite, isNull);
  });

  test('一般成員看到待審申請在待決定，但待辦不會要他審核', () {
    final captain = member('cap', MemberRole.captain);
    final regular = member('m1', MemberRole.member);
    final board = DecisionBoard.build(
      trip: trip(expectedReturnAt: DateTime.utc(2026, 11, 5, 9)),
      self: regular,
      members: [captain, regular],
      requests: [request()],
      invites: const [],
      now: now,
    );

    expect(titles(board, BoardSection.pending), [AppStrings.boardRequests]);
    expect(board.section(BoardSection.todo), isEmpty);
    expect(
      titles(board, BoardSection.decided),
      contains(AppStrings.expectedReturn),
    );
  });

  test('隊長的待辦有審核申請；8 人以上沒有副隊長時要指定副隊長', () {
    final captain = member('cap', MemberRole.captain);
    final others = [
      for (var i = 0; i < 7; i++) member('m$i', MemberRole.member),
    ];
    final board = DecisionBoard.build(
      trip: trip(expectedReturnAt: DateTime.utc(2026, 11, 5, 9)),
      self: captain,
      members: [captain, ...others],
      requests: [request()],
      invites: const [],
      now: now,
    );

    expect(
      titles(board, BoardSection.todo),
      containsAll([
        AppStrings.boardReviewRequests(1),
        AppStrings.boardAssignVice,
      ]),
    );
  });

  test('過期的申請不算待決定', () {
    final captain = member('cap', MemberRole.captain);
    final board = DecisionBoard.build(
      trip: trip(expectedReturnAt: DateTime.utc(2026, 11, 5, 9)),
      self: captain,
      members: [captain, member('m1', MemberRole.member)],
      requests: [request()],
      invites: const [],
      now: now.add(const Duration(hours: 1)),
    );

    expect(board.section(BoardSection.pending), isEmpty);
    expect(board.section(BoardSection.todo), isEmpty);
  });

  test('旅途中待辦優先，接著已決定；旅程結束只剩已決定', () {
    final captain = member('cap', MemberRole.captain);
    final active = DecisionBoard.build(
      trip: trip(status: TripStatus.active),
      self: captain,
      members: [captain],
      requests: const [],
      invites: const [],
      now: now,
    );
    expect(active.order, [
      BoardSection.todo,
      BoardSection.decided,
      BoardSection.pending,
    ]);

    final ended = DecisionBoard.build(
      trip: trip(status: TripStatus.ended),
      self: captain,
      members: [captain],
      requests: [request()],
      invites: [invite()],
      now: now,
    );
    expect(ended.order, [BoardSection.decided]);
    expect(ended.section(BoardSection.todo), isEmpty);
  });

  test('分享文字可以單獨閱讀：有標題、各區塊與邀請碼', () {
    final captain = member('cap', MemberRole.captain);
    final board = DecisionBoard.build(
      trip: trip(),
      self: captain,
      members: [captain],
      requests: const [],
      invites: [invite()],
      now: now,
    );
    final text = board.shareText();

    expect(text, startsWith(AppStrings.boardShareTitle('京都自由行')));
    expect(text, contains('【${AppStrings.boardTodo}】'));
    expect(text, contains('【${AppStrings.boardPending}】'));
    expect(text, contains('【${AppStrings.boardDecided}】'));
    expect(text, contains(AppStrings.boardShareInviteLine('CODE0001')));
    expect(
      text.indexOf(AppStrings.boardTodo),
      lessThan(text.indexOf(AppStrings.boardDecided)),
    );
    expect(
      DecisionBoard.inviteShareText(board.trip, board.shareableInvite!),
      AppStrings.inviteShareText('京都自由行', 'CODE0001'),
    );
  });
}
