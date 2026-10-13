import 'package:flutter_test/flutter_test.dart';
import 'package:{{name}}/presentation/presenters/welcome/change_notifier_welcome_presenter.dart';

void main() {
  test('a new session should not have started', () {
    final ChangeNotifierWelcomePresenter presenter =
        ChangeNotifierWelcomePresenter();

    expect(presenter.hasStarted, false);
  });

  test('starting should mark the session and tell the listeners once', () {
    final ChangeNotifierWelcomePresenter presenter =
        ChangeNotifierWelcomePresenter();
    int notified = 0;
    presenter.addListener(() => notified++);

    presenter.start();
    presenter.start();

    expect(presenter.hasStarted, true);
    expect(notified, 1);
  });
}
