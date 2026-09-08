import 'dart:io';

import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:test/test.dart';

import 'support/repo_root.dart';

/// O contrato de nomes entre o que `dovetail build` embute e o que o app le
/// com `String.fromEnvironment`. Sao duas strings em dois pacotes, ligadas
/// por nada em tempo de compilacao: renomear uma delas deixa o app com o
/// padrao do codigo e o build dizendo que embutiu — em silencio.
void main() {
  test('every define the build emits should be read by the product', () {
    final File appReleaseFile = File(
      inRepo(<String>[
        'product',
        'vpn_desktop',
        'lib',
        'main',
        'app_release.dart',
      ]),
    );
    if (!appReleaseFile.existsSync()) {
      markTestSkipped(
        'este contrato mede um app real contra os defines que o build emite, '
        'e o app do produto não mora no repositório público. Rode-o no '
        'monorepo que carrega product/, ou aponte um app seu.',
      );
      return;
    }
    final String appRelease = appReleaseFile.readAsStringSync();

    for (final String define in <String>[
      BuildDefines.publicKey,
      BuildDefines.endpoint,
      BuildDefines.version,
    ]) {
      expect(
        appRelease,
        contains("String.fromEnvironment(\n    '$define'"),
        reason: '$define e embutido pelo build e o app nao o le',
      );
    }
  });
}
