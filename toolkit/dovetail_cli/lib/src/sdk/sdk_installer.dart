import 'dart:io';

import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:path/path.dart' as p;

/// Extrai o tarball do SDK no home do locator e aponta o symlink do binário.
///
/// O tarball carrega `bin/dovetail` e `sdk/<versão>/` na raiz; extrair no
/// home deixa cada versão no próprio diretório, então instalar 0.2.0 ao
/// lado de 0.1.0 não toca o que os apps apontados para a anterior resolvem
/// — o aceite do self-update é justamente isso.
final class SdkInstaller {
  SdkInstaller({
    required this.home,
    this._binDir,
    this._runner = const SystemProcessRunner(),
  });

  final String home;
  final ProcessRunner _runner;
  final String? _binDir;

  /// Onde o symlink mora: o parâmetro (seam de teste), depois
  /// `$DOVETAIL_BIN_DIR` — o mesmo env que o `tool/sdk/install.sh` respeita,
  /// para os dois instaladores concordarem — e por fim `~/.local/bin`.
  String get binDir =>
      _binDir ??
      Platform.environment['DOVETAIL_BIN_DIR'] ??
      p.join(Platform.environment['HOME'] ?? home, '.local', 'bin');

  /// Desempacota [tarball] no home e devolve o caminho do binário instalado.
  Future<String> extract(File tarball) async {
    Directory(home).createSync(recursive: true);
    final ProcessOutcome outcome = await _runner.run('tar', <String>[
      '-xzf',
      tarball.path,
      '-C',
      home,
    ], timeout: const Duration(minutes: 5));
    if (!outcome.succeeded) {
      throw UpdateFailure(
        'tar could not unpack ${tarball.path}: ${outcome.firstDiagnostic}.',
        remedy:
            'The download verified against its sha256, so this is a '
            'local tar problem, not a corrupted release.',
      );
    }
    return p.join(home, 'bin', 'dovetail');
  }

  /// Cria (ou troca) o symlink `dovetail` em [binDir] apontando para o
  /// binário instalado, e avisa quando o diretório está fora do PATH.
  Link linkBin() {
    Directory(binDir).createSync(recursive: true);
    final Link link = Link(p.join(binDir, 'dovetail'));
    if (link.existsSync()) {
      link.deleteSync();
    }
    link.createSync(p.join(home, 'bin', 'dovetail'));

    final List<String> path = (Platform.environment['PATH'] ?? '').split(
      Platform.isWindows ? ';' : ':',
    );
    if (!path.contains(binDir)) {
      stdout.writeln('  note: $binDir is not in PATH');
    }
    return link;
  }
}
