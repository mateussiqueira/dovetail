import 'package:flutter/foundation.dart';

abstract class WelcomePresenter implements Listenable {
  bool get hasStarted;

  void start();
  void dispose();
}
