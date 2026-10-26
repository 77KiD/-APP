import 'package:flutter/material.dart';
import 'package:group_trip/app/app_scope.dart';
import 'package:group_trip/core/widgets/form_widgets.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/presentation/trip_detail_page.dart';
import 'package:group_trip/l10n/app_strings.dart';

class JoinTripPage extends StatefulWidget {
  const JoinTripPage({super.key});

  @override
  State<JoinTripPage> createState() => _JoinTripPageState();
}

class _JoinTripPageState extends State<JoinTripPage> {
  final _code = TextEditingController();
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
          LabeledField(
            label: AppStrings.inviteCodeField,
            controller: _code,
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
