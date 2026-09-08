import 'package:flutter/material.dart';
import 'package:{{name}}/presentation/presenters/home/home_presenter.dart';
import 'package:{{name}}/presentation/ui/widgets/home/greeting_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.presenter});

  final HomePresenter presenter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: GreetingCard(presenter: presenter)),
    );
  }
}
