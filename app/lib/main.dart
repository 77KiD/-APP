import 'package:flutter/widgets.dart';
import 'package:group_trip/app/composition.dart';
import 'package:group_trip/app/travel_app.dart';
import 'package:timezone/data/latest.dart' as tzdata;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  final dependencies = await buildAppDependencies();
  runApp(TravelApp(deps: dependencies));
}
