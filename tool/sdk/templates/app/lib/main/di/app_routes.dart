import 'package:flutter/material.dart';
import 'package:{{name}}/main/factories/pages/home_page_factory.dart';
import 'package:{{name}}/shared/constants/route_names.dart';

final Map<String, WidgetBuilder> appRoutes = <String, WidgetBuilder>{
  RouteNames.home: (BuildContext context) => makeHomePage(),
};
