import 'package:{{name}}/presentation/presenters/welcome/change_notifier_welcome_presenter.dart';
import 'package:{{name}}/presentation/presenters/welcome/welcome_presenter.dart';
import 'package:weave_di/weave_di.dart';

WeaveModule welcomeModule() => WeaveModule(
  name: 'welcome',
  binds: <WeaveBind>[
    (WeaveContainer c) {
      c.bindLazy<WelcomePresenter>(
        ChangeNotifierWelcomePresenter.new,
        dispose: (WelcomePresenter p) => p.dispose(),
      );
    },
  ],
  exports: const <WeaveExport<Object?>>[WeaveExport<WelcomePresenter>()],
);
