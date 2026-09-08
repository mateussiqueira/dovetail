import 'package:flutter/foundation.dart';
import 'package:{{name}}/domain/entities/greeting_entity.dart';
import 'package:{{name}}/domain/usecases/home/load_greeting.dart';
import 'package:{{name}}/presentation/mixins/error_handling_mixin.dart';
import 'package:{{name}}/presentation/mixins/loading_mixin.dart';
import 'package:{{name}}/presentation/presenters/home/home_presenter.dart';

class ChangeNotifierHomePresenter extends ChangeNotifier
    with LoadingMixin, ErrorHandlingMixin
    implements HomePresenter {
  ChangeNotifierHomePresenter({required this._loadGreeting});

  final LoadGreeting _loadGreeting;

  GreetingEntity? _greeting;

  @override
  GreetingEntity? get greeting => _greeting;

  @override
  Future<void> load() async {
    _greeting = await withLoading(() => guard(_loadGreeting.call));
  }
}
