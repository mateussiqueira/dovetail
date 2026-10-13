import 'package:flutter/widgets.dart';
import 'package:weave_di/weave_di.dart';

class SessionGuard implements WeaveRedirectingGuard {
  const SessionGuard({required this.hasSession, required this.welcomePath});

  final bool Function() hasSession;
  final String welcomePath;

  @override
  Future<WeaveGuardResult> resolve(
    BuildContext context,
    String route,
    WeaveParams params,
    List<WeaveRoute> matchedRoutes,
  ) async {
    if (hasSession()) {
      return const WeaveGuardResult.allow();
    }
    return WeaveGuardResult.redirect(welcomePath);
  }

  @override
  Future<bool> canActivate(
    BuildContext context,
    String route,
    WeaveParams params,
    List<WeaveRoute> matchedRoutes,
  ) async => hasSession();
}
