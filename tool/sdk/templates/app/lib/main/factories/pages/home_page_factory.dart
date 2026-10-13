import 'package:flutter/material.dart';
import 'package:{{name}}/presentation/presenters/home/home_presenter.dart';
import 'package:{{name}}/presentation/ui/pages/home_page.dart';
import 'package:weave_di/weave_di.dart';

Widget makeHomePage(WeaveContainer c) =>
    HomePage(presenter: c.get<HomePresenter>());
