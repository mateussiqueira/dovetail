import 'package:flutter/material.dart';
import 'package:{{name}}/main/di/app_routes.dart';
import 'package:{{name}}/shared/constants/route_names.dart';

void main() {
  runApp(const {{camel_name}}App());
}

class {{camel_name}}App extends StatelessWidget {
  const {{camel_name}}App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '{{name}}',
      debugShowCheckedModeBanner: false,
      routes: appRoutes,
      initialRoute: RouteNames.home,
    );
  }
}
