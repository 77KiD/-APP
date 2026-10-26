import 'package:flutter/material.dart';
import 'package:group_trip/app/app_scope.dart';
import 'package:group_trip/core/widgets/form_widgets.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/features/trip/presentation/trip_detail_page.dart';
import 'package:group_trip/l10n/app_strings.dart';

class CreateTripPage extends StatefulWidget {
  const CreateTripPage({required this.initialTimeZone, super.key});

  final String initialTimeZone;

  @override
  State<CreateTripPage> createState() => _CreateTripPageState();
}

class _CreateTripPageState extends State<CreateTripPage> {
  late final TextEditingController _title;
  final _start = TextEditingController();
  final _end = TextEditingController();
  late final TextEditingController _zone;
  final _returnDate = TextEditingController();
  final _returnTime = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _zone = TextEditingController(text: widget.initialTimeZone);
  }

  @override
  void dispose() {
    _title.dispose();
    _start.dispose();
    _end.dispose();
    _zone.dispose();
    _returnDate.dispose();
    _returnTime.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final deps = AppScope.of(context);
    final form = NewTripForm(
      title: _title.text,
      startDate: _start.text,
      endDate: _end.text,
      timeZone: _zone.text,
      returnDate: _returnDate.text,
      returnTime: _returnTime.text,
    );
    try {
      final trip = await deps.trips.createTrip(form);
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
      appBar: AppBar(title: const Text(AppStrings.createTrip)),
      body: FormColumn(
        children: [
          const PageHeading(AppStrings.createTrip),
          LabeledField(label: AppStrings.tripTitle, controller: _title),
          LabeledField(
            label: AppStrings.startDate,
            controller: _start,
            hint: AppStrings.dateHint,
            helper: AppStrings.dateHelper,
            keyboardType: TextInputType.datetime,
          ),
          LabeledField(
            label: AppStrings.endDate,
            controller: _end,
            hint: AppStrings.dateHint,
            helper: AppStrings.dateHelper,
            keyboardType: TextInputType.datetime,
          ),
          LabeledField(
            label: AppStrings.timeZone,
            controller: _zone,
            helper: AppStrings.timeZoneHelper,
          ),
          Text(
            AppStrings.expectedReturnOptional,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          LabeledField(
            label: AppStrings.returnDate,
            controller: _returnDate,
            hint: AppStrings.dateHint,
            helper: AppStrings.dateHelper,
            keyboardType: TextInputType.datetime,
          ),
          LabeledField(
            label: AppStrings.returnTime,
            controller: _returnTime,
            hint: AppStrings.timeHint,
            helper: AppStrings.timeHelper,
            keyboardType: TextInputType.datetime,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          FormErrorText(_error),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: const Text(AppStrings.submitCreateTrip),
          ),
        ],
      ),
    );
  }
}
