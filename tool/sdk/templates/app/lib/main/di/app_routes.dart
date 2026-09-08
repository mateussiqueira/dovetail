import 'package:flutter/material.dart';
import 'package:{{name}}/main/factories/pages/home_page_factory.dart';
import 'package:{{name}}/shared/constants/route_names.dart';
import 'package:weave_di/weave_di.dart';

final WeaveRouter appRouter = WeaveRouter(
  routes: <WeaveRoute>[
    WeaveRoute(
      path: '/',
      name: RouteNames.home,
      injectFactory:
          (BuildContext context, WeaveParams params, WeaveContainer c) =>
              makeHomePage(c),
    ),
  ],
);

final RouteFactory appRouteFactory = appRouter.routeFactory;

List<Route<dynamic>> appInitialRoutes(String initialRoute) =>
    appRouter.onGenerateInitialRoutes(initialRoute);
