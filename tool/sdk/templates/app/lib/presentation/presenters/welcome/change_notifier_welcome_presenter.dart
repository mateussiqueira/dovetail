import 'package:flutter/foundation.dart';
import 'package:{{name}}/presentation/presenters/welcome/welcome_presenter.dart';

class ChangeNotifierWelcomePresenter extends ChangeNotifier
    implements WelcomePresenter {
  bool _started = false;

  @override
  bool get hasStarted => _started;

  @override
  void start() {
    if (_started) {
      return;
    }
    _started = true;
    notifyListeners();
  }
}
