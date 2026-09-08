import 'package:{{name}}/domain/entities/greeting_entity.dart';

abstract class LoadGreeting {
  Future<GreetingEntity> call();
}
