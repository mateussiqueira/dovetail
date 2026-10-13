import 'package:{{name}}/data/usecases/local_load_greeting.dart';
import 'package:{{name}}/domain/usecases/home/load_greeting.dart';
import 'package:{{name}}/infra/clock/system_clock_provider.dart';
import 'package:{{name}}/presentation/presenters/home/change_notifier_home_presenter.dart';
import 'package:{{name}}/presentation/presenters/home/home_presenter.dart';

LoadGreeting makeLoadGreeting() =>
    LocalLoadGreeting(clock: SystemClockProvider());

HomePresenter makeHomePresenter() =>
    ChangeNotifierHomePresenter(loadGreeting: makeLoadGreeting());
