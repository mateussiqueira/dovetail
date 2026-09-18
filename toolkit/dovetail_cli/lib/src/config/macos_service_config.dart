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
    required this.binary,
    required this.route,
    required this.arguments,
    this.entitlements,
    this.instructions,
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
    if (program.contains('&') ||
        program.contains('<') ||
        program.contains('>')) {
      throw ConfigFailure(
        'service.macos.program is "$program", which carries a character '
        'XML reserves.',
        remedy:
            'the name becomes a file inside Contents/MacOS, a relative path '
            'the signing step looks up, and a plist entry — only the last '
            'of the three would decode XML entities. Name the binary '
            'something the filesystem, the signer and the plist all agree '
            'on.',
        origin: origin,
      );
    }

    final String binary = _required(map, 'binary', origin);

    final Object? entitlements = map['entitlements'];
    if (entitlements != null && entitlements is! String) {
      throw ConfigFailure(
        'service.macos.entitlements must be a path.',
        origin: origin,
      );
    }

    final Object? instructions = map['instructions'];
    if (instructions != null && instructions is! String) {
      throw ConfigFailure(
        'service.macos.instructions must be a path.',
        origin: origin,
      );
    }

    return MacosServiceConfig(
      label: label,
      program: program,
      binary: binary,
      route: _routeOf(map, origin),
      arguments: _arguments(map, origin),
      entitlements: entitlements as String?,
      instructions: instructions as String?,
    );
  }

  /// O rótulo do daemon no launchd — `com.example.app.helper`.
  final String label;

  /// O nome do binário dentro do bundle.
  final String program;

  /// Onde encontrar o binário AGORA, relativo à raiz do projeto.
  ///
  /// Separado de [program] porque são duas coisas: onde ele foi construído
  /// nesta máquina, e o nome que ele recebe dentro do bundle. Esta ferramenta
  /// não compila o daemon — não conhece a cadeia de build de quem a usa —, e
  /// recusa alto quando o arquivo não está lá.
  final String binary;

  /// O que o daemon recebe na linha de comando, depois do próprio caminho.
  final List<String> arguments;

  /// Por onde o daemon chega à máquina. Ver [DarwinServiceRoute].
  final DarwinServiceRoute route;

  /// Entitlements do DAEMON, que não são os do aplicativo.
  ///
  /// Nulo é o caso comum: um daemon sem entitlements é o que a maioria dos
  /// produtos quer. O que ele nunca pode herdar é o `app-sandbox` do
  /// aplicativo — um daemon em sandbox não alcança rede, disco nem socket
  /// fora do contêiner, que é tudo o que ele existe para fazer.
  final String? entitlements;

  final String? instructions;

  /// O arquivo que o `SMAppService` procura dentro do bundle.
  ///
  /// O nome é o rótulo com `.plist`, e não uma escolha: o `SMAppService`
  /// resolve o daemon pelo nome do arquivo, e um plist cujo `Label` divirja do
  /// nome não registra.
  String get plistFileName => '$label.plist';

  static List<String> _arguments(Map<String, Object?> map, String origin) {
    final Object? value = map['arguments'];
    if (value == null) {
      return const <String>[];
    }
    if (value is! List) {
      throw ConfigFailure(
        'service.macos.arguments must be a list.',
        origin: origin,
      );
    }
    return <String>[
      for (final Object? entry in value)
        if (entry is String)
          entry
        else
          throw ConfigFailure(
            'service.macos.arguments holds a non-string entry.',
            origin: origin,
          ),
    ];
  }

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
