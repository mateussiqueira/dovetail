import 'package:flutter/material.dart';
import 'package:{{name}}/main/di/home_module.dart';
import 'package:{{name}}/presentation/ui/pages/home_page.dart';

Widget makeHomePage() => HomePage(presenter: makeHomePresenter());
