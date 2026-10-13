import 'package:flutter/material.dart';
import 'package:{{name}}/presentation/presenters/welcome/welcome_presenter.dart';
import 'package:{{name}}/shared/i18n/welcome_strings.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({
    super.key,
    required this.presenter,
    required this.onStarted,
  });

  final WelcomePresenter presenter;
  final void Function(BuildContext context) onStarted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(WelcomeStrings.title),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                presenter.start();
                onStarted(context);
              },
              child: const Text(WelcomeStrings.start),
            ),
          ],
        ),
      ),
    );
  }
}
