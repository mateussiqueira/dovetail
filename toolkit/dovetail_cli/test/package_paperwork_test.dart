import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

/// Todo pacote deste repositório carrega os mesmos quatro arquivos.
///
/// Três estavam sem `LICENSE` quando isto foi escrito — `dovetail`,
/// `dovetail_form_validation` e `dovetail_process_runner` — e dois sem `CHANGELOG.md`. Nada
/// quebrava por isso, e é justamente o problema: um pacote publicado sem os
/// termos dentro dele viaja sem os termos, e ninguém descobre isso
/// compilando — o pub.dev aceita e a licença simplesmente não está lá.
///
/// Os dois primeiros pacotes nasceram hoje; o `dovetail` estava assim desde
/// que existe. Papelada é o tipo de coisa que só falta quando ninguém confere.
const List<String> _required = <String>[
  'README.md',
  'CHANGELOG.md',
  'LICENSE',
  'analysis_options.yaml',
];

/// Onde os pacotes moram. O repositório público carrega o toolkit; o
/// produto que o consome vive em outro lugar.
const List<String> _trees = <String>['toolkit'];

Iterable<Directory> _packages() sync* {
  for (final String tree in _trees) {
    final Directory root = Directory(p.join(repoRoot(), tree));
    for (final FileSystemEntity entity in root.listSync()) {
      if (entity is Directory &&
          File(p.join(entity.path, 'pubspec.yaml')).existsSync()) {
        yield entity;
      }
    }
  }
}

void main() {
  late List<Directory> packages;

  setUpAll(() {
    packages = _packages().toList()
      ..sort((Directory a, Directory b) => a.path.compareTo(b.path));
  });

  test('the sweep should find every package, or it is proving nothing', () {
    expect(
      packages,
      hasLength(greaterThanOrEqualTo(10)),
      reason:
          'eram 12 quando isto foi escrito. Um punhado significa que a árvore '
          'mudou de forma e todas as outras asserções aqui ficaram vazias.',
    );
  });

  test('every package should carry the same four files', () {
    final List<String> missing = <String>[
      for (final Directory package in packages)
        for (final String file in _required)
          if (!File(p.join(package.path, file)).existsSync())
            '${p.basename(package.parent.path)}/'
                '${p.basename(package.path)}: $file',
    ];

    expect(missing, isEmpty);
  });

  test('the licence should be the same text in every package', () {
    // Não é formalidade: dois textos diferentes num repositório proprietário
    // é uma pergunta sobre qual vale, e a resposta custa advogado.
    final Set<String> texts = <String>{
      for (final Directory package in packages)
        File(p.join(package.path, 'LICENSE')).readAsStringSync().trim(),
    };

    expect(
      texts,
      hasLength(1),
      reason: 'há ${texts.length} textos de licença diferentes na árvore',
    );
    expect(texts.single, contains('MIT License'));
  });

  test('a changelog should say something, not just carry a heading', () {
    for (final Directory package in packages) {
      final List<String> lines = File(p.join(package.path, 'CHANGELOG.md'))
          .readAsLinesSync()
          .map((String line) => line.trim())
          .where((String line) => line.isNotEmpty && !line.startsWith('#'))
          .toList();

      expect(
        lines,
        isNotEmpty,
        reason:
            '${p.basename(package.path)}/CHANGELOG.md só tem título — um '
            'changelog vazio é pior que nenhum, porque parece mantido',
      );
    }
  });
}
