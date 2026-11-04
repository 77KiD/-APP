import 'package:flutter/material.dart';
import 'package:group_trip/app/app_scope.dart';
import 'package:group_trip/core/widgets/form_widgets.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/presentation/trip_detail_page.dart';
import 'package:group_trip/l10n/app_strings.dart';

class JoinTripPage extends StatefulWidget {
  const JoinTripPage({this.initialCode, super.key});

  /// 從邀請連結 `/j/<邀請碼>` 打開時先填好（ADR 0012 第 3 點）。
  final String? initialCode;

  @override
  State<JoinTripPage> createState() => _JoinTripPageState();
}

class _JoinTripPageState extends State<JoinTripPage> {
  late final _code = TextEditingController(text: widget.initialCode ?? '');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final deps = AppScope.of(context);
    try {
      final trip = await deps.trips.joinWithInviteCode(_code.text);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TripDetailPage(tripId: trip.id)),
      );
    } on InviteNotFoundException {
      if (!mounted) return;
      // 本機模式下別人手機上的碼一定找不到，要講清楚原因，不能只說找不到。
      setState(
        () => _error = deps.firebaseConfigured
            ? AppStrings.inviteNotFound
            : AppStrings.localModeInviteNotFound,
      );
    } on TripException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.joinTitle)),
      body: FormColumn(
        children: [
          const PageHeading(AppStrings.joinTitle),
          if (!AppScope.of(context).firebaseConfigured)
            const Text(
              AppStrings.localModeInviteNotice,
              key: Key('local-mode-invite-notice'),
            ),
          LabeledField(
            label: AppStrings.inviteCodeField,
            controller: _code,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          FormErrorText(_error),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: const Text(AppStrings.submitJoin),
          ),
        ],
      ),
    );
  }
}
