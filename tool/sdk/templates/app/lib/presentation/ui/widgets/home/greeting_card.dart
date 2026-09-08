import 'package:flutter/material.dart';
import 'package:{{name}}/domain/entities/greeting_entity.dart';
import 'package:{{name}}/presentation/errors/ui_error.dart';
import 'package:{{name}}/presentation/presenters/home/home_presenter.dart';
import 'package:{{name}}/shared/i18n/home_strings.dart';

class GreetingCard extends StatefulWidget {
  const GreetingCard({super.key, required this.presenter});

  final HomePresenter presenter;

  @override
  State<GreetingCard> createState() => _GreetingCardState();
}

class _GreetingCardState extends State<GreetingCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.presenter.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.presenter,
      builder: (BuildContext context, Widget? _) {
        final GreetingEntity? greeting = widget.presenter.greeting;
        final UIError? error = widget.presenter.error;
        if (widget.presenter.isLoading && greeting == null) {
          return const CircularProgressIndicator();
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(greeting?.message ?? HomeStrings.welcome),
            if (error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(HomeStrings.loadFailed),
            ],
          ],
        );
      },
    );
  }
}
