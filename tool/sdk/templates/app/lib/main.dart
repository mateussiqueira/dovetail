import 'package:flutter/material.dart';
import 'package:{{name}}/main/di/app_routes.dart';
import 'package:{{name}}/main/di/root_module.dart';
import 'package:weave_di/weave_di.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await (WeaveModuleRegistry()..register(rootModule())).installAll();
  runApp(const {{camel_name}}App());
}

class {{camel_name}}App extends StatelessWidget {
  const {{camel_name}}App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '{{name}}',
      debugShowCheckedModeBanner: false,
      onGenerateRoute: appRouteFactory,
      onGenerateInitialRoutes: appInitialRoutes,
      initialRoute: '/',
    );
  }
}
