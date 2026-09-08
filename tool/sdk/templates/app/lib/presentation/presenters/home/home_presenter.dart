import 'package:flutter/foundation.dart';
import 'package:{{name}}/domain/entities/greeting_entity.dart';
import 'package:{{name}}/presentation/errors/ui_error.dart';

abstract class HomePresenter implements Listenable {
  GreetingEntity? get greeting;
  UIError? get error;
  bool get isLoading;

  Future<void> load();
  void dispose();
}
