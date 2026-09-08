import 'package:flutter_test/flutter_test.dart';
import 'package:{{name}}/domain/entities/greeting_entity.dart';
import 'package:{{name}}/domain/usecases/home/load_greeting.dart';
import 'package:{{name}}/presentation/presenters/home/change_notifier_home_presenter.dart';

class LoadGreetingStub implements LoadGreeting {
  const LoadGreetingStub(this.result);

  final GreetingEntity result;

  @override
  Future<GreetingEntity> call() async => result;
}

void main() {
  test('should expose the greeting loaded by the usecase', () async {
    final ChangeNotifierHomePresenter presenter = ChangeNotifierHomePresenter(
      loadGreeting: LoadGreetingStub(const GreetingEntity(message: 'Olá')),
    );

    await presenter.load();

    expect(presenter.greeting?.message, 'Olá');
    expect(presenter.isLoading, false);
    expect(presenter.error, isNull);
  });
}
