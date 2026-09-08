import 'dart:convert';

import 'package:crypto/crypto.dart';

/// O UpgradeCode do MSI, derivado do `identifier` — UUID v5 (SHA-1) sobre o
/// namespace URL da RFC 4122 e o texto `dovetail:<identifier>`.
///
/// O Windows Installer usa o UpgradeCode para saber que um MSI novo SUBSTITUI
/// o instalado: dois releases do mesmo produto tem de carregar o mesmo, e dois
/// produtos nunca o mesmo. Gerar um aleatorio por build e o jeito de um update
/// instalar ao lado do anterior em vez de por cima; pedir um a mao e mais uma
/// linha para alguem esquecer — e era o que acontecia: o `ship` pedia
/// `--windows-format msi` sem `--upgrade-code`, e o `bundle` recusava. Derivar
/// do identifier da estabilidade sem configuracao: mudar o identifier e mudar
/// de produto, e para o Windows Installer tambem.
final class UpgradeCode {
  const UpgradeCode._();

  static const String _urlNamespace = '6ba7b8119dad11d180b400c04fd430c8';

  static String forIdentifier(String identifier) {
    final List<int> name = <int>[
      ..._bytes(_urlNamespace),
      ...utf8.encode('dovetail:$identifier'),
    ];
    final List<int> digest = sha1.convert(name).bytes.sublist(0, 16);
    digest[6] = (digest[6] & 0x0f) | 0x50; // versao 5
    digest[8] = (digest[8] & 0x3f) | 0x80; // variante RFC 4122
    final String hex = digest
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static List<int> _bytes(String hex) => List<int>.generate(
    hex.length ~/ 2,
    (int i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
  );
}
