import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

/// O índice de `docs/` cita todo documento do repositório, e todo link dele
/// resolve.
///
/// São vinte e dois documentos. Um que o índice não cita é um documento que
/// ninguém encontra, e um documento que ninguém encontra não está escrito. O
/// caminho inverso é pior: link quebrado num índice ensina quem lê a não
/// confiar nele, e aí os que funcionam também param de ser seguidos.
///
/// A varredura ignora `CHANGELOG.md`, que é por pacote e alcançado pelo README
/// dele, e o que é gerado ou vendorizado.
/// Um por idioma. Um documento e encontravel se **algum** dos dois o cita:
/// o indice ingles carrega os documentos em ingles, o portugues os em
/// portugues, e exigir que o ingles cite os dois lados faria a metade
/// traduzida parecer orfa.
List<File> _indexes() => <File>[
  File(p.join(repoRoot(), 'docs', 'README.md')),
  File(p.join(repoRoot(), 'docs', 'pt-BR', 'README.md')),
];

const List<String> _ignoredPaths = <String>[
  '/build/',
  '/Pods/',
  '/cargokit/',
  '/ephemeral/',
  '/graphify-out/',
  '/.git/',
];

/// Documentos deliberadamente fora do índice, com o motivo escrito.
const Map<String, String> _notIndexed = <String, String>{
  'docs/README.md': 'é o próprio índice',
  'docs/pt-BR/README.md': 'é o próprio índice, do outro idioma',
};

Iterable<String> _documents() sync* {
  for (final FileSystemEntity entity in Directory(
    repoRoot(),
  ).listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.md')) {
      continue;
    }
    if (p.basename(entity.path) == 'CHANGELOG.md') {
      continue;
    }
    final String relative = p.relative(entity.path, from: repoRoot());
    if (_ignoredPaths.any((String each) => '/$relative'.contains(each))) {
      continue;
    }
    yield relative;
  }
}

void main() {
  late List<String> documents;
  late String index;

  setUpAll(() {
    documents = _documents().toList()..sort();
    index = _indexes().map((File each) => each.readAsStringSync()).join('\n');
  });

  test('the sweep should find the documents, or it is proving nothing', () {
    expect(
      documents,
      hasLength(greaterThan(15)),
      reason: 'eram 22 quando isto foi escrito',
    );
    expect(documents, contains('README.md'));
    expect(documents, contains('ESCREVER_O_APP.md'));
    expect(documents, contains('WRITING_THE_APP.md'));
  });

  /// Um `X.pt-BR.md` nao precisa estar num indice: ele e alcancado pelo
  /// seletor de idioma no topo do `X.md`, que esta. Exigir os dois lados em
  /// todo indice dobraria cada tabela sem dizer nada novo — mas o par tem de
  /// existir e tem de apontar, e e isso que o teste seguinte cobra.
  bool _reachedByItsPair(String document) {
    if (!document.endsWith('.pt-BR.md')) {
      return false;
    }
    final String pair = document.replaceAll('.pt-BR.md', '.md');
    final File pairFile = File(p.join(repoRoot(), pair));
    return pairFile.existsSync() &&
        pairFile.readAsStringSync().contains(p.basename(document));
  }

  test('every document should be linked from the index', () {
    final List<String> orphaned = <String>[
      for (final String document in documents)
        if (!_notIndexed.containsKey(document) &&
            !_reachedByItsPair(document) &&
            !index.contains(p.basename(document)) &&
            !index.contains(document))
          document,
    ]..sort();

    expect(
      orphaned,
      isEmpty,
      reason:
          'estes documentos existem e o índice não os cita — documento que '
          'ninguém encontra não está escrito',
    );
  });

  test('a bilingual pair should point at each other', () {
    final List<String> oneWay = <String>[
      for (final String document in documents)
        if (document.endsWith('.pt-BR.md'))
          if (!File(
                p.join(repoRoot(), document.replaceAll('.pt-BR.md', '.md')),
              ).existsSync() ||
              !File(
                p.join(repoRoot(), document),
              ).readAsStringSync().contains(']('))
            document,
    ]..sort();

    expect(
      oneWay,
      isEmpty,
      reason:
          'um documento traduzido sem o seletor de idioma no topo é um beco '
          'sem saída: quem chega nele não encontra o outro lado',
    );
  });

  test('every link in the index should resolve', () {
    final List<String> broken = <String>[
      for (final RegExpMatch match in RegExp(
        r'\]\((\.\.?/[^)#]+|[a-z][a-z0-9._-]*\.md)\)',
      ).allMatches(index))
        if (!File(
              p.normalize(p.join(repoRoot(), 'docs', match.group(1)!)),
            ).existsSync() &&
            !File(
              p.normalize(p.join(repoRoot(), 'docs', 'pt-BR', match.group(1)!)),
            ).existsSync())
          match.group(1)!,
    ];

    expect(
      broken,
      isEmpty,
      reason:
          'link quebrado num índice ensina quem lê a não confiar nele, e aí '
          'os que funcionam também param de ser seguidos',
    );
  });

  test('an unindexed document should carry a written reason', () {
    for (final MapEntry<String, String> excuse in _notIndexed.entries) {
      expect(
        documents,
        contains(excuse.key),
        reason: '"${excuse.key}" está dispensado e já não existe',
      );
      expect(excuse.value.trim(), isNotEmpty);
    }
  });
}
