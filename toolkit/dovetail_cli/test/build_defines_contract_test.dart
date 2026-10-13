import 'dart:io';

import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

/// O contrato de nomes entre o que `dovetail build` embute e o que o app le
/// com `String.fromEnvironment`. Sao duas strings em dois pacotes, ligadas
/// por nada em tempo de compilacao: renomear uma delas deixa o app com o
/// padrao do codigo e o build dizendo que embutiu — em silencio.
void main() {
  test('every define the build emits should be read by the product', () {
    final String declared =
        Platform.environment['DOVETAIL_PRODUCT']?.trim() ?? '';
    final Directory lib = Directory(
      p.join(
        p.isAbsolute(declared) ? declared : inRepo(<String>[declared]),
        'lib',
      ),
    );
    if (declared.isEmpty || !lib.existsSync()) {
      markTestSkipped(
        'set DOVETAIL_PRODUCT to an app root to measure its lib/ against '
        'the defines the build emits',
      );
      return;
    }
    final String appSource = <String>[
      for (final FileSystemEntity entity in lib.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          entity.readAsStringSync(),
    ].join('\n');

    for (final String define in <String>[
      BuildDefines.publicKey,
      BuildDefines.endpoint,
      BuildDefines.version,
    ]) {
      expect(
        appSource,
        matches(
          RegExp("String\\.fromEnvironment\\(\\s*'${RegExp.escape(define)}'"),
        ),
        reason: '$define e embutido pelo build e o app nao o le',
      );
    }
  });
}
