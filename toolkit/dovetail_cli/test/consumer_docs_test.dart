import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

/// `docs/problemas.md` é lido por quem tem um projeto GERADO, não por quem
/// está neste monorepo. Um remédio que manda rodar `dart tool/verify.dart`
/// manda para um arquivo que o leitor não tem — aconteceu com três entradas,
/// reescritas em 2026-09-06 no vocabulário do scaffold (`make codegen`,
/// `dovetail dev`, `make tests`). O que é só do monorepo pode ficar, desde
/// que DIGA que é: num parágrafo em itálico que começa com `*(` e nomeia o
/// monorepo, como os três que já existem.
const List<String> _repoOnly = <String>['tool/verify.dart', 'product/'];

/// A marca vale nos dois idiomas: o documento existe em ingles no caminho
/// canonico e em portugues ao lado, e a regra e sobre o que o leitor de um
/// projeto gerado encontra — nao sobre em que lingua ele le.
bool _isMonorepoNote(String paragraph) =>
    paragraph.trimLeft().startsWith('*(') &&
    RegExp(
      'monorepo do dovetail|dovetail monorepo',
      caseSensitive: false,
    ).hasMatch(paragraph);

/// Os dois lados do par bilingue, porque a regra vale para quem le qualquer
/// um deles.
const List<List<String>> _bothLanguages = <List<String>>[
  <String>['docs', 'problemas.md'],
  <String>['docs', 'pt-BR', 'problemas.md'],
];

void main() {
  late List<String> paragraphs;

  setUpAll(() {
    paragraphs = <String>[
      for (final List<String> each in _bothLanguages)
        ...File(
          p.joinAll(<String>[repoRoot(), ...each]),
        ).readAsStringSync().split(RegExp(r'\n\s*\n')),
    ];
  });

  test(
    'a repo-only path in problemas.md should sit inside a marked monorepo note',
    () {
      final List<String> unmarked = <String>[
        for (final String paragraph in paragraphs)
          if (_repoOnly.any(paragraph.contains) && !_isMonorepoNote(paragraph))
            paragraph.trim().split('\n').first,
      ];

      expect(
        unmarked,
        isEmpty,
        reason:
            'estes parágrafos mandam quem tem um projeto gerado a um caminho '
            'que só existe neste repositório, sem dizer isso — ou reescreva no '
            'vocabulário do scaffold, ou marque como nota do monorepo (*(…)*)',
      );
    },
  );

  test('the marked notes should exist, or the rule is guarding nothing', () {
    expect(
      paragraphs.where(_isMonorepoNote),
      hasLength(greaterThanOrEqualTo(6)),
      reason: 'eram três em 2026-09-06, e agora somam os dois idiomas',
    );
  });
}
