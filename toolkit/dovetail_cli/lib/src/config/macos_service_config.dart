import 'package:dovetail_cli/src/config/config_failure.dart';
import 'package:dovetail_cli/src/config/darwin_service_route.dart';

/// O componente privilegiado no macOS.
///
/// A seção `service` existia e era de Linux inteira — unidade systemd e
/// política polkit. O macOS tem a mesma necessidade e nenhuma declaração: o
/// daemon não entrava no bundle, o `SMAppService` não achava plist nenhum, e a
/// tela dizia "não instalado" sobre algo que nunca chegou a ser empacotado.
final class MacosServiceConfig {
  const MacosServiceConfig({
    required this.label,
    required this.program,
    required this.route,
    this.entitlements,
  });

  factory MacosServiceConfig.fromMap(
    Map<String, Object?> map,
    String origin, {
    required String identifier,
  }) {
    final String label = _required(map, 'label', origin);
    if (!label.startsWith('$identifier.')) {
      throw ConfigFailure(
        'the daemon label "$label" is outside the "$identifier" namespace.',
        remedy:
            'launchd and SMAppService look the daemon up by a label the system '
            'expects inside the app own namespace; a label declared outside it '
            'registers and never matches.',
        origin: origin,
      );
    }

    final String program = _required(map, 'program', origin);
    if (program.contains('/')) {
      throw ConfigFailure(
        'service.macos.program is "$program", which is a path.',
        remedy:
            'the binary is copied INTO the bundle, so what goes here is the '
            'file name it gets there — the path where it was built changes '
            'with the machine.',
        origin: origin,
      );
    }

    final Object? entitlements = map['entitlements'];
    if (entitlements != null && entitlements is! String) {
      throw ConfigFailure(
        'service.macos.entitlements must be a path.',
        origin: origin,
      );
    }

    return MacosServiceConfig(
      label: label,
      program: program,
      route: _routeOf(map, origin),
      entitlements: entitlements as String?,
    );
  }

  /// O rótulo do daemon no launchd — `com.example.app.helper`.
  final String label;

  /// O nome do binário dentro do bundle.
  final String program;

  /// Por onde o daemon chega à máquina. Ver [DarwinServiceRoute].
  final DarwinServiceRoute route;

  /// Entitlements do DAEMON, que não são os do aplicativo.
  ///
  /// Nulo é o caso comum: um daemon sem entitlements é o que a maioria dos
  /// produtos quer. O que ele nunca pode herdar é o `app-sandbox` do
  /// aplicativo — um daemon em sandbox não alcança rede, disco nem socket
  /// fora do contêiner, que é tudo o que ele existe para fazer.
  final String? entitlements;

  /// O arquivo que o `SMAppService` procura dentro do bundle.
  ///
  /// O nome é o rótulo com `.plist`, e não uma escolha: o `SMAppService`
  /// resolve o daemon pelo nome do arquivo, e um plist cujo `Label` divirja do
  /// nome não registra.
  String get plistFileName => '$label.plist';

  static DarwinServiceRoute _routeOf(Map<String, Object?> map, String origin) {
    final Object? value = map['route'];
    if (value == null) {
      return DarwinServiceRoute.bundled;
    }
    return switch (value) {
      'bundled' => DarwinServiceRoute.bundled,
      'system' => DarwinServiceRoute.system,
      _ => throw ConfigFailure(
        'service.macos.route is "$value".',
        remedy:
            'it is "bundled" (the daemon travels inside the app and registers '
            'with SMAppService) or "system" (an installer running as root puts '
            'it in /Library/LaunchDaemons).',
        origin: origin,
      ),
    };
  }

  static String _required(Map<String, Object?> map, String key, String origin) {
    final Object? value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw ConfigFailure('service.macos.$key is missing.', origin: origin);
    }
    return value;
  }
}
