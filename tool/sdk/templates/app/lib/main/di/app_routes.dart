import 'package:flutter/material.dart';
import 'package:{{name}}/main/factories/pages/home_page_factory.dart';
import 'package:{{name}}/main/factories/pages/welcome_page_factory.dart';
import 'package:{{name}}/main/guards/session_guard.dart';
import 'package:{{name}}/presentation/presenters/welcome/welcome_presenter.dart';
import 'package:{{name}}/shared/constants/route_names.dart';
import 'package:weave_di/weave_di.dart';

final SessionGuard sessionGuard = SessionGuard(
  hasSession: () =>
      WeaveContainerAdapter.global.get<WelcomePresenter>().hasStarted,
  welcomePath: '/welcome',
);

final WeaveRouter appRouter = WeaveRouter(
  routes: <WeaveRoute>[
    WeaveRoute(
      path: '/',
      name: RouteNames.home,
      guards: <WeaveRouteGuard>[sessionGuard],
      injectFactory:
          (BuildContext context, WeaveParams params, WeaveContainer c) =>
              makeHomePage(c),
    ),
    WeaveRoute(
      path: '/welcome',
      name: RouteNames.welcome,
      skipGuards: true,
      injectFactory:
          (BuildContext context, WeaveParams params, WeaveContainer c) =>
              makeWelcomePage(
                c,
                onStarted: (BuildContext context) =>
                    context.replaceRoute<void>(appRouter, '/'),
              ),
    ),
  ],
);

final RouteFactory appRouteFactory = appRouter.routeFactory;

List<Route<dynamic>> appInitialRoutes(String initialRoute) =>
    appRouter.onGenerateInitialRoutes(initialRoute);
