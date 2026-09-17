import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

/// `tool/release.sh` é a orquestração: o que sai numa versão passou por um
/// canário que prova que o consumidor consegue usar o artefato.
///
/// O `prove_service.sh` provou o bundle do daemon sozinho, com runner de
/// gravação, e não tinha dono nenhum no release — a versão saía carregando o
/// daemon sem ninguém provar o bundle em que ele cai. Um canário que existe e
/// nenhum release roda é uma prova que ninguém paga: verde para sempre, e
/// invisível para quem corta a versão.
///
/// A varredura é por texto contra o `release.sh`, e prende a INVOCAÇÃO
/// (`bash tool/ci/<nome>`), nunca a menção — a lista de passos do cabeçalho
/// cita os mesmos arquivos e não roda nenhum deles.
File _release() => File(inRepo(<String>['tool', 'release.sh']));

Directory _ci() => Directory(inRepo(<String>['tool', 'ci']));

/// Os canários que um OUTRO dono roda, com o motivo escrito. Cada entrada aqui
/// é uma afirmação de que o release não é o lugar dele; a lista é curta de
/// propósito, e o teste seguinte impede que ela vire o esconderijo de um
/// canário que deveria estar no release.
const Map<String, String> _ownedElsewhere = <String, String>{
  'prove_update.sh':
      'o alvo `release` do verify.dart roda a pipeline macOS inteira contra um '
      'host local, sobre um .app já construído — não é o que o release publica',
};

List<String> _canaries() => <String>[
  for (final FileSystemEntity each in _ci().listSync())
    if (each is File &&
        p.basename(each.path).startsWith('prove_') &&
        each.path.endsWith('.sh'))
      p.basename(each.path),
]..sort();

/// Invocado como passo do release, e não apenas citado no cabeçalho.
bool _isRunBy(String script, String canary) =>
    script.contains('bash tool/ci/$canary');

void main() {
  late String script;

  setUpAll(() => script = _release().readAsStringSync());

  test('every canary in tool/ci should be run by the release, or name its '
      'owner', () {
    final List<String> orphans = <String>[
      for (final String canary in _canaries())
        if (!_isRunBy(script, canary) && !_ownedElsewhere.containsKey(canary))
          canary,
    ];

    expect(
      orphans,
      isEmpty,
      reason:
          'estes canários existem em tool/ci e nenhum release os roda: ou '
          'acrescente o passo em tool/release.sh, ou declare em _ownedElsewhere '
          'quem os roda e por quê',
    );
  });

  test(
    'the daemon canary should be a release step, not a listed exception',
    () {
      expect(
        _canaries(),
        hasLength(greaterThanOrEqualTo(3)),
        reason: 'com menos de três a varredura não prova nada sobre o release',
      );
      expect(_ownedElsewhere, isNot(contains('prove_service.sh')));
      expect(_isRunBy(script, 'prove_service.sh'), isTrue);
    },
  );
}
