import 'dart:convert';

import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/src/config/dovetail_config.dart';

/// O que o `dovetail build` embute no app a partir do `dovetail.yaml`, como
/// `--dart-define`. E o ponto de troca unica: a chave publica que o app
/// confia e o endpoint que ele consulta saem do MESMO arquivo que o `release`
/// usa para assinar e o `probe` para verificar. Antes, a chave morava numa
/// constante do app e no yaml, ligadas so por um teste que pula quando
/// `keys/` nao existe — e foi assim que saiu um release assinado por uma
/// chave que o app recusava.
///
/// O app le com `String.fromEnvironment('dovetail.update.public_key',
/// defaultValue: ...)`: um `flutter run` sem o dovetail continua com os
/// padroes do produto; um `dovetail build` embute o que o yaml diz.
final class BuildDefines {
  const BuildDefines._();

  static const String identifier = 'dovetail.identifier';
  static const String version = 'dovetail.version';
  static const String baseUrl = 'dovetail.update.base_url';
  static const String endpoint = 'dovetail.update.endpoint';
  static const String publicKey = 'dovetail.update.public_key';

  static Map<String, String> of({
    required DovetailConfig config,
    String? appVersion,
  }) {
    final String? key = config.update?.publicKey;
    return <String, String>{
      identifier: config.identifier,
      version: ?appVersion,
      if (config.update?.baseUrl != null) baseUrl: config.update!.baseUrl!,
      if (config.update?.endpoint != null) endpoint: config.update!.endpoint!,
      // Uma linha, na forma que o keygen imprime e o tauri.conf.json guarda:
      // base64 por cima do texto minisign. `MinisignPublicKey.unwrap` aceita
      // as duas, entao o app nao precisa saber qual recebeu.
      if (key != null)
        publicKey: base64.encode(utf8.encode(MinisignPublicKey.unwrap(key))),
    };
  }

  /// Uma linha por define, com a chave publica resumida ao key id — para o
  /// build dizer o que embutiu sem despejar base64 no terminal.
  static Iterable<String> describe(Map<String, String> defines) sync* {
    for (final MapEntry<String, String> entry in defines.entries) {
      if (entry.key == publicKey) {
        yield '${entry.key}=<key ${MinisignPublicKey.parse(entry.value).keyIdHex}>';
      } else {
        yield '${entry.key}=${entry.value}';
      }
    }
  }
}
