import 'package:{{name}}/data/protocols/clock/clock_provider.dart';

class SystemClockProvider implements ClockProvider {
  @override
  DateTime now() => DateTime.now();
}
