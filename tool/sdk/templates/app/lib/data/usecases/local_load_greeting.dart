import 'package:{{name}}/data/protocols/clock/clock_provider.dart';
import 'package:{{name}}/domain/entities/greeting_entity.dart';
import 'package:{{name}}/domain/usecases/home/load_greeting.dart';

class LocalLoadGreeting implements LoadGreeting {
  const LocalLoadGreeting({required this._clock});

  final ClockProvider _clock;

  @override
  Future<GreetingEntity> call() async {
    final int hour = _clock.now().hour;
    final String message = switch (hour) {
      >= 5 && < 12 => 'Bom dia',
      >= 12 && < 18 => 'Boa tarde',
      _ => 'Boa noite',
    };
    return GreetingEntity(message: message);
  }
}
