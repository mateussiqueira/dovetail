import 'package:flutter/material.dart';
import 'package:{{name}}/presentation/presenters/welcome/welcome_presenter.dart';
import 'package:{{name}}/presentation/ui/pages/welcome_page.dart';
import 'package:weave_di/weave_di.dart';

Widget makeWelcomePage(
  WeaveContainer c, {
  required void Function(BuildContext context) onStarted,
}) => WelcomePage(presenter: c.get<WelcomePresenter>(), onStarted: onStarted);
