import 'package:flutter/material.dart';
import 'package:group_trip/core/theme/app_colors.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/l10n/app_strings.dart';

class MemberAvatar extends StatelessWidget {
  const MemberAvatar({required this.name, super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : String.fromCharCode(name.runes.first);
    return Semantics(
      container: true,
      label: AppStrings.avatarLabel(name),
      image: true,
      child: ExcludeSemantics(
        child: CircleAvatar(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          child: Text(initial),
        ),
      ),
    );
  }
}

class RoleChip extends StatelessWidget {
  const RoleChip({required this.role, super.key});

  final MemberRole role;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (role) {
      MemberRole.captain => (
        AppColors.captainBackground,
        AppColors.captainForeground,
      ),
      MemberRole.viceCaptain => (
        AppColors.viceBackground,
        AppColors.viceForeground,
      ),
      MemberRole.member => (
        AppColors.memberBackground,
        AppColors.memberForeground,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          role.label,
          style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
