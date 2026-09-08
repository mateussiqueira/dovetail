import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:test/test.dart';

import 'support/repo_root.dart';

/// Todo comando registrado tem de aparecer no README, e o contrário também.
///
/// Três comandos tinham escapado quando este teste foi escrito — `keygen`,
/// `manifest` e `probe`. Nenhum deles estava quebrado: eles simplesmente não
/// existiam para quem lê. Um comando que ninguém sabe que existe custa o mesmo
/// que um comando que não existe, e a diferença só aparece quando alguém
/// reescreve à mão o que já estava pronto.
///
/// A checagem é por texto porque a documentação é texto. O que ela prende é a
/// existência da menção, não a qualidade dela.
/// Os DOIS READMEs que prometem comandos, e nao so o do pacote.
///
/// Era `Directory.current.path`, e a suite roda de dentro de
/// `toolkit/dovetail_cli/`: a checagem lia o README do PACOTE e ficava verde
/// enquanto o README da RAIZ — a primeira pagina que alguem le, e a que
/// carrega o bloco "A esteira, comando por comando" — listava 13 dos 19
/// comandos registrados. `dev`, `bridge`, `keygen`, `new`, `update` e
/// `upgrade` existiam e nao apareciam ali. Um teste que passa por apontar
/// para o arquivo errado e pior do que nenhum: ele parece cobrir.
Map<String, File> _readmes() => <String, File>{
  'toolkit/dovetail_cli/README.md': File(
    inRepo(<String>['toolkit', 'dovetail_cli', 'README.md']),
  ),
  'README.md': File(inRepo(<String>['README.md'])),
};

/// Comandos deliberadamente fora do README, com o motivo escrito. Vazio hoje,
/// e a lista existe para que uma omissão futura seja uma decisão registrada em
/// vez de um esquecimento silencioso.
const Map<String, String> _deliberatelyUndocumented = <String, String>{};

CommandRunner<int> _runner() => CommandRunner<int>('dovetail', 'a esteira')
  ..addCommand(InitCommand())
  ..addCommand(DoctorCommand())
  ..addCommand(DevCommand())
  ..addCommand(BridgeCommand())
  ..addCommand(BuildCommand())
  ..addCommand(BundleCommand())
  ..addCommand(SignCommand())
  ..addCommand(IconCommand())
  ..addCommand(KeygenCommand())
  ..addCommand(InspectCommand())
  ..addCommand(ManifestCommand())
  ..addCommand(NewCommand())
  ..addCommand(ProbeCommand())
  ..addCommand(ReleaseCommand())
  ..addCommand(SelfInstallCommand())
  ..addCommand(SelfUpdateCommand())
  ..addCommand(ShipCommand())
  ..addCommand(UpdateCommand())
  ..addCommand(UpgradeCommand());

void main() {
  late List<String> registered;
  late Map<String, String> readmes;

  setUpAll(() {
    // `help` é do próprio CommandRunner, não deste binário: contá-lo faria o
    // teste comparar 13 com os 12 que bin/dovetail.dart registra.
    registered =
        (_runner().commands.keys.where((String each) => each != 'help').toList()
          ..sort());
    readmes = <String, String>{
      for (final MapEntry<String, File> each in _readmes().entries)
        each.key: each.value.readAsStringSync(),
    };
  });

  test('the list this test checks should match bin/dovetail.dart', () {
    // Sem isto, o teste passa a conferir uma lista sua própria: alguém
    // acrescenta um comando ao binário, esquece deste arquivo, e a checagem
    // segue verde sobre um conjunto que já não é o real.
    final String entrypoint = File(
      inRepo(<String>['toolkit', 'dovetail_cli', 'bin', 'dovetail.dart']),
    ).readAsStringSync();

    // A classe vira o nome do comando: SelfInstallCommand → self-install.
    String kebab(String className) {
      final StringBuffer out = StringBuffer();
      for (final String char in className.split('')) {
        if (char == char.toUpperCase() && out.isNotEmpty) {
          out.write('-');
        }
        out.write(char.toLowerCase());
      }
      return out.toString();
    }

    final Set<String> inBinary = RegExp(r'addCommand\((\w+)Command\(\)\)')
        .allMatches(entrypoint)
        .map((RegExpMatch match) => kebab(match.group(1)!))
        .toSet();

    expect(
      inBinary,
      registered.toSet(),
      reason:
          'bin/dovetail.dart registra ${inBinary.length} comando(s) e este '
          'teste monta ${registered.length}',
    );
  });

  test('every command should be named in both READMEs', () {
    for (final MapEntry<String, String> readme in readmes.entries) {
      final List<String> missing = <String>[
        for (final String command in registered)
          if (!_deliberatelyUndocumented.containsKey(command) &&
              !readme.value.contains('dovetail $command'))
            command,
      ];

      expect(
        missing,
        isEmpty,
        reason:
            'estes comandos existem e não aparecem em ${readme.key}: um '
            'comando que ninguém sabe que existe custa o mesmo que um que não '
            'existe',
      );
    }
  });

  test('neither README should promise a command that is gone', () {
    final Set<String> promised = <String>{
      for (final String readme in readmes.values)
        ...RegExp(
          r'dovetail ([a-z][a-z-]+)',
        ).allMatches(readme).map((RegExpMatch match) => match.group(1)!),
    };

    // `dovetail init` na prosa e `dovetail help` são reais; qualquer outra
    // palavra depois de `dovetail ` que pareça comando e não seja é o que
    // interessa aqui.
    const Set<String> notCommands = <String>{'help', 'yaml'};

    expect(
      promised.difference(registered.toSet()).difference(notCommands),
      isEmpty,
      reason:
          'o README manda rodar algo que o binário não registra, o que é pior '
          'que não documentar: quem seguir recebe "unknown command"',
    );
  });

  test('an undocumented command should carry a written reason', () {
    for (final MapEntry<String, String> excuse
        in _deliberatelyUndocumented.entries) {
      expect(
        registered,
        contains(excuse.key),
        reason:
            '"${excuse.key}" está dispensado de um README que já não o cita',
      );
      expect(
        excuse.value.trim(),
        isNotEmpty,
        reason: '"${excuse.key}" está fora do README sem motivo escrito',
      );
    }
  });
}
