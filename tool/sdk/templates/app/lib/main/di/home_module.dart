import 'package:{{name}}/data/protocols/clock/clock_provider.dart';
import 'package:{{name}}/data/usecases/local_load_greeting.dart';
import 'package:{{name}}/domain/usecases/home/load_greeting.dart';
import 'package:{{name}}/infra/clock/system_clock_provider.dart';
import 'package:{{name}}/presentation/presenters/home/change_notifier_home_presenter.dart';
import 'package:{{name}}/presentation/presenters/home/home_presenter.dart';
import 'package:weave_di/weave_di.dart';

/// A feature home, um escopo do grafo.
///
/// Só o presenter é exportado — os usecases e o protocolo de relógio existem
/// para montá-lo, e nada além deste módulo precisa conhecê-los.
WeaveModule homeModule() => WeaveModule(
  name: 'home',
  binds: <WeaveBind>[
    (WeaveContainer c) {
      c.bindLazy<ClockProvider>(SystemClockProvider.new);
      c.bindLazy<LoadGreeting>(
        () => LocalLoadGreeting(clock: c.get<ClockProvider>()),
      );
      c.bindLazy<HomePresenter>(
        () => ChangeNotifierHomePresenter(loadGreeting: c.get<LoadGreeting>()),
        dispose: (HomePresenter p) => p.dispose(),
      );
    },
  ],
  exports: const <WeaveExport<Object?>>[WeaveExport<HomePresenter>()],
);
