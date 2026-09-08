import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// O CLI compilado UMA vez por corrida, para as suítes que o executam como
/// processo.
///
/// `dart run bin/dovetail.dart` recompila o CLI inteiro do zero em cada
/// invocação — medido em ~1,58s, e `doctor_command_test` o invoca dezoito
/// vezes. Eram ~28s de uma suíte de ~30s gastos compilando a mesma coisa,
/// dentro do pacote que domina o alvo `test`.
///
/// `dart compile kernel` custa ~0,9s uma vez, e cada `dart <dill>` depois
/// disso custa ~0,18s.
///
/// Compilado a partir do MESMO `bin/dovetail.dart` que a suíte testa, num
/// diretório temporário por corrida: um snapshot reaproveitado entre corridas
/// testaria o CLI de ontem, que é pior do que o custo que ele evita.
final class CliKernel {
  const CliKernel._();

  static String? _dill;
  static Directory? _out;
  static bool _installed = false;

  /// Registra a limpeza. Chame do corpo de `main()`, no tempo de DECLARAÇÃO —
  /// `tearDownAll` não pode ser registrado de dentro de um `setUpAll` já em
  /// execução, e tentar isso falha a suíte inteira com "Can't call
  /// tearDownAll() once tests have begun running".
  ///
  /// O compile NÃO acontece aqui. Ele é preguiçoso, na primeira chamada a
  /// [run]: um `setUpAll` que compilasse sempre cobraria ~5s de qualquer
  /// `dart test -n "<nome>"` que selecionasse só testes que nunca sobem o CLI —
  /// medido, três testes puros passavam de 1,2s para 3,4-5,0s. O portão nunca
  /// paga isso (roda o pacote inteiro), mas quem itera num teste paga a cada
  /// tecla.
  static void install() {
    _installed = true;
    tearDownAll(() {
      _dill = null;
      final Directory? out = _out;
      _out = null;
      // Nulo quando nenhum teste chamou `run`: nada foi compilado, nada a
      // apagar. Um `late` aqui viraria LateInitializationError no teardown de
      // toda corrida filtrada.
      if (out != null && out.existsSync()) {
        out.deleteSync(recursive: true);
      }
    });
  }

  static String _ensureCompiled() {
    if (!_installed) {
      throw StateError(
        'CliKernel.run before install(): call CliKernel.install() from the '
        'body of main(), not from inside a setUp — without it the compiled '
        'snapshot is never cleaned up.',
      );
    }
    final String? ready = _dill;
    if (ready != null) {
      return ready;
    }

    _sweepStale();
    final Directory out = Directory.systemTemp.createTempSync('dovetail_dill');
    _out = out;
    final String entryPoint = p.join(
      Directory.current.path,
      'bin',
      'dovetail.dart',
    );
    final String dill = p.join(out.path, 'dovetail.dill');
    final ProcessResult compiled = Process.runSync(_dart, <String>[
      'compile',
      'kernel',
      entryPoint,
      '-o',
      dill,
    ], workingDirectory: Directory.current.path);

    // Falha ALTO. Um fallback silencioso para `dart run` devolveria o custo
    // sem ninguém perceber — que é como ele chegou aqui.
    if (compiled.exitCode != 0 || !File(dill).existsSync()) {
      throw StateError(
        'could not compile $entryPoint to a kernel snapshot.\n'
        '${compiled.stderr}\n${compiled.stdout}',
      );
    }
    return _dill = dill;
  }

  /// Varre kernels de corridas que morreram antes do `tearDownAll`.
  ///
  /// O `tearDownAll` é a única limpeza, e um Ctrl+C comum basta para ele não
  /// rodar: o `package:test_core` trata SIGINT fechando o engine, e o laço de
  /// entradas retorna ANTES do bloco de teardown (engine.dart:365). Reproduzido
  /// — um SIGINT no meio da suíte deixa 19,7 MB de `dovetail.dill` para trás,
  /// todas as vezes. Isso é do runner, não daqui, então a resposta é varrer o
  /// que sobrou de corridas anteriores.
  ///
  /// Uma hora de idade é a margem: uma corrida viva tem segundos, e outra
  /// corrida concorrente — que existe nesta máquina — não pode ter o diretório
  /// apagado debaixo dela. Não reaproveita snapshot entre corridas: apaga, não
  /// lê.
  static void _sweepStale() {
    final DateTime cutoff = DateTime.now().subtract(const Duration(hours: 1));
    for (final FileSystemEntity each in Directory.systemTemp.listSync(
      followLinks: false,
    )) {
      if (each is! Directory ||
          !p.basename(each.path).startsWith('dovetail_dill')) {
        continue;
      }
      try {
        if (each.statSync().modified.isBefore(cutoff)) {
          each.deleteSync(recursive: true);
        }
      } on FileSystemException {
        // Outra corrida pode ter apagado primeiro; não é falha nossa.
      }
    }
  }

  /// O `dart` que está rodando ESTA suíte, e não o primeiro `dart` do PATH.
  ///
  /// Duas razões, medidas. O `dart` do PATH nesta máquina é um wrapper em
  /// bash do Flutter que pega um `flock` no cache a cada invocação — ~0,13s
  /// vezes dezesseis processos, e pior sob a concorrência da suíte: a suíte
  /// inteira caiu de 12,4s para 5,8s trocando dois identificadores. E fixa o
  /// compile e as execuções no MESMO SDK que roda o `dart test`, o que importa
  /// num PATH que carrega um Dart do Flutter e outro do Homebrew.
  ///
  /// Só vale porque `dovetail_cli` é um pacote `dart` na tabela do
  /// `tool/verify.dart`: num pacote `flutter`, `resolvedExecutable` seria o
  /// `flutter_tester`, e isto quebraria.
  static String get _dart => Platform.resolvedExecutable;

  /// Roda o CLI. Mesma assinatura de um `dart run`, sem a recompilação.
  static ProcessResult run(
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) => Process.runSync(
    _dart,
    <String>[_ensureCompiled(), ...arguments],
    workingDirectory: workingDirectory,
    environment: environment,
  );
}
