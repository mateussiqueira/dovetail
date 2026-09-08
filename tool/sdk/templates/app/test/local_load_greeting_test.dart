import 'package:flutter_test/flutter_test.dart';
import 'package:{{name}}/data/protocols/clock/clock_provider.dart';
import 'package:{{name}}/data/usecases/local_load_greeting.dart';

class FakeClock implements ClockProvider {
  const FakeClock(this.time);

  final DateTime time;

  @override
  DateTime now() => time;
}

void main() {
  test('should greet in the morning', () async {
    final LocalLoadGreeting usecase = LocalLoadGreeting(
      clock: FakeClock(DateTime(2026, 1, 1, 8)),
    );

    expect((await usecase()).message, 'Bom dia');
  });

  test('should greet in the afternoon', () async {
    final LocalLoadGreeting usecase = LocalLoadGreeting(
      clock: FakeClock(DateTime(2026, 1, 1, 14)),
    );

    expect((await usecase()).message, 'Boa tarde');
  });

  test('should greet at night', () async {
    final LocalLoadGreeting usecase = LocalLoadGreeting(
      clock: FakeClock(DateTime(2026, 1, 1, 22)),
    );

    expect((await usecase()).message, 'Boa noite');
  });
}
