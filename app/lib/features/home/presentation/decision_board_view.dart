import 'package:flutter/material.dart';
import 'package:group_trip/core/theme/semantic_colors.dart';
import 'package:group_trip/core/theme/spacing.dart';
import 'package:group_trip/features/home/domain/decision_board.dart';
import 'package:group_trip/l10n/app_strings.dart';

/// 決定看板：已決定／待決定／我的待辦，順序依旅程階段（ADR 0011）。
class DecisionBoardView extends StatelessWidget {
  const DecisionBoardView({
    required this.board,
    required this.onAction,
    required this.onShareBoard,
    super.key,
  });

  final DecisionBoard board;
  final ValueChanged<BoardAction> onAction;
  final VoidCallback onShareBoard;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      key: const Key('decision-board'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${AppStrings.boardTitle}・${board.trip.title}',
          style: textTheme.titleLarge?.copyWith(color: colors.text),
        ),
        const SizedBox(height: AppSpacing.s2),
        for (final section in board.order)
          _Section(
            section: section,
            items: board.section(section),
            onAction: onAction,
          ),
        OutlinedButton.icon(
          key: const Key('share-board'),
          onPressed: onShareBoard,
          icon: const Icon(Icons.share_outlined),
          label: const Text(AppStrings.boardShare),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.section,
    required this.items,
    required this.onAction,
  });

  final BoardSection section;
  final List<BoardItem> items;
  final ValueChanged<BoardAction> onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    // 待辦即使是空的也顯示，讓人知道「目前沒有我要做的事」。
    if (items.isEmpty && section != BoardSection.todo) {
      return const SizedBox.shrink();
    }
    final accent = switch (section) {
      BoardSection.todo => colors.accent,
      BoardSection.pending => colors.amber,
      BoardSection.decided => colors.green,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s3),
      // ListTile 的點擊水波要畫在 Material 上，所以底色與外框用 Material 畫。
      child: Material(
        key: Key('board-${section.name}'),
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: colors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Text(
                    section.label,
                    style: textTheme.titleMedium?.copyWith(color: colors.text),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s2),
              if (items.isEmpty)
                Text(
                  AppStrings.boardNothingToDo,
                  style: textTheme.bodyMedium?.copyWith(color: colors.muted),
                ),
              for (final item in items)
                _ItemTile(item: item, onAction: onAction),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onAction});

  final BoardItem item;
  final ValueChanged<BoardAction> onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final action = item.action;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 48,
      title: Text(
        item.title,
        style: textTheme.bodyLarge?.copyWith(color: colors.text),
      ),
      subtitle: item.detail == null
          ? null
          : Text(
              item.detail!,
              style: textTheme.bodyMedium?.copyWith(color: colors.muted),
            ),
      trailing: switch (action) {
        BoardAction.shareInvite => Icon(
          Icons.share_outlined,
          color: colors.primaryInk,
        ),
        BoardAction.openTrip => Icon(Icons.chevron_right, color: colors.dim),
        null => null,
      },
      onTap: action == null ? null : () => onAction(action),
    );
  }
}
