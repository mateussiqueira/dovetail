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
File _index() => File(p.join(repoRoot(), 'docs', 'README.md'));

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
    index = _index().readAsStringSync();
  });

  test('the sweep should find the documents, or it is proving nothing', () {
    expect(
      documents,
      hasLength(greaterThan(15)),
      reason: 'eram 22 quando isto foi escrito',
    );
    expect(documents, contains('README.md'));
    expect(documents, contains('ESCREVER_O_APP.md'));
  });

  test('every document should be linked from the index', () {
    final List<String> orphaned = <String>[
      for (final String document in documents)
        if (!_notIndexed.containsKey(document) &&
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

  test('every link in the index should resolve', () {
    final List<String> broken = <String>[
      for (final RegExpMatch match in RegExp(
        r'\]\((\.\.?/[^)#]+|[a-z][a-z0-9._-]*\.md)\)',
      ).allMatches(index))
        if (!File(
          p.normalize(p.join(repoRoot(), 'docs', match.group(1)!)),
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
