import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

/// Toda chave do `dovetail.yaml` que o parser lê tem de estar documentada, e
/// nada documentado pode ser chave que o parser não conhece.
///
/// A referência estava incompleta quando isto foi escrito: `manufacturer`,
/// `update.public-key`, `update.unencrypted`, `sign.macos.entitlements` e
/// `sign.windows.password-env` eram lidos e não apareciam em documento nenhum.
/// Chave que existe e ninguém documenta é chave que ninguém usa; chave
/// documentada que não existe é pior, porque quem seguir escreve YAML que o
/// parser ignora em silêncio.
///
/// A leitura é por texto, contra o código do parser. Ela prende a existência
/// da menção, não a qualidade dela.
File _reference() => File(p.join(repoRoot(), 'docs', 'configuracao.md'));

Directory _parsers() => Directory(
  p.join(repoRoot(), 'toolkit', 'dovetail_cli', 'lib', 'src', 'config'),
);

/// Strings que aparecem no diretório de config e **não** são chave do YAML.
///
/// A varredura é por texto, então ela pega o que o parser lê e também nomes de
/// arquivo, valores padrão e palavras de mensagem. Cada exclusão aqui é uma
/// afirmação de que aquela string não é chave — e o teste seguinte confere que
/// nenhuma delas virou chave sem ninguém notar.
const Map<String, String> _notKeys = <String, String>{
  'app': 'prefixo do template escrito pelo init',
  'assets': 'diretório que o project_probe procura, não chave da config',
  'icons': 'idem',
  'images': 'idem',
  'runner': 'idem',
  'darwin': 'palavra do vocabulário de alvo, não chave',
  'linux': 'idem',
  'http': 'esquema de url dentro de uma mensagem',
  'version': 'lido do pubspec.yaml, e deliberadamente ausente daqui',
};

/// Chaves que dois blocos diferentes compartilham. Documentar `password-env`
/// uma vez em `update` e outra em `sign.windows` é o certo; o teste conta
/// menção, e uma basta.
Set<String> _keysReadByTheParser() {
  final Set<String> found = <String>{};
  for (final FileSystemEntity file in _parsers().listSync()) {
    if (!file.path.endsWith('.dart')) {
      continue;
    }
    final String source = File(file.path).readAsStringSync();
    for (final RegExpMatch match in RegExp(
      r"'([a-z][a-z-]{2,})'",
    ).allMatches(source)) {
      final String candidate = match.group(1)!;
      if (candidate.contains('.') || _notKeys.containsKey(candidate)) {
        continue;
      }
      found.add(candidate);
    }
  }
  return found;
}

void main() {
  late Set<String> keys;
  late String reference;

  setUpAll(() {
    keys = _keysReadByTheParser();
    reference = _reference().readAsStringSync();
  });

  test('the sweep should find the keys, or it is proving nothing', () {
    // Eram 22 quando isto foi escrito. Um punhado significa que o parser mudou
    // de forma e as asserções abaixo ficaram vazias.
    expect(keys, hasLength(greaterThan(15)));
    expect(keys, containsAll(<String>['identifier', 'targets', 'exec-start']));
  });

  test('every key the parser reads should be named in the reference', () {
    // `macos.identity-env` documenta `identity-env`, e exigir a chave nua
    // faria o teste pedir que a referência a repetisse sem o bloco — o que a
    // deixaria pior de ler para satisfazer a checagem.
    final List<String> undocumented = <String>[
      for (final String key in keys)
        if (!RegExp(
          '`(?:[a-z-]+\\.)*${RegExp.escape(key)}`',
        ).hasMatch(reference))
          key,
    ]..sort();

    expect(
      undocumented,
      isEmpty,
      reason:
          'estas chaves existem e não estão em docs/configuracao.md — chave '
          'que ninguém documenta é chave que ninguém usa',
    );
  });

  test('the reference should not promise a key the parser ignores', () {
    // Só as citadas em bloco de código YAML: a prosa fala de `--artifact` e de
    // outras coisas que não são chave.
    final Iterable<RegExpMatch> yaml = RegExp(
      r'```yaml\n(.*?)```',
      dotAll: true,
    ).allMatches(reference);
    final Set<String> promised = <String>{
      for (final RegExpMatch block in yaml)
        for (final RegExpMatch line in RegExp(
          r'^\s*([a-z][a-z-]+):',
          multiLine: true,
        ).allMatches(block.group(1)!))
          line.group(1)!,
    };

    expect(
      promised.difference(keys),
      isEmpty,
      reason:
          'o exemplo manda escrever chave que o parser não lê, e YAML que o '
          'parser ignora é ignorado em silêncio',
    );
  });

  test('an exclusion should not be quietly covering a real key', () {
    for (final MapEntry<String, String> excuse in _notKeys.entries) {
      expect(
        excuse.value.trim(),
        isNotEmpty,
        reason: '"${excuse.key}" está excluído sem motivo escrito',
      );
      expect(
        reference.contains('`${excuse.key}`:'),
        isFalse,
        reason:
            '"${excuse.key}" está na lista de não-chaves e a referência o '
            'documenta como chave — um dos dois está errado',
      );
    }
  });
}
