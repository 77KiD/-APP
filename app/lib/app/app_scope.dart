import 'package:flutter/widgets.dart';
import 'package:group_trip/app/app_dependencies.dart';

class AppScope extends InheritedWidget {
  const AppScope({required this.deps, required super.child, super.key});

  final AppDependencies deps;

  static AppDependencies of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope 不在這個 widget 上面');
    return scope!.deps;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.deps != deps;
}
