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
    p.Context? context,
    Map<String, String>? environment,
  }) : _context = context ?? p.context,
       _environment = environment ?? Platform.environment;

  final String home;
  final ProcessRunner _runner;
  final String? _binDir;
  final p.Context _context;
  final Map<String, String> _environment;

  bool get _isWindows => _context.style == p.Style.windows;

  String get installedBinary =>
      _context.join(home, 'bin', _isWindows ? 'dovetail.exe' : 'dovetail');

  /// Onde o symlink mora: o parâmetro (seam de teste), depois
  /// `$DOVETAIL_BIN_DIR` — o mesmo env que o `tool/sdk/install.sh` respeita,
  /// para os dois instaladores concordarem — e por fim `~/.local/bin`.
  String get binDir =>
      _binDir ??
      _environment['DOVETAIL_BIN_DIR'] ??
      _context.join(
        (_isWindows
                ? _environment['USERPROFILE'] ?? _environment['HOME']
                : _environment['HOME'] ?? _environment['USERPROFILE']) ??
            home,
        '.local',
        'bin',
      );

  /// Desempacota [tarball] no home e devolve o caminho do binário instalado.
  Future<String> extract(File tarball) async {
    Directory(home).createSync(recursive: true);
    final ProcessOutcome outcome = await _runner.run('tar', <String>[
      _isWindows ? '-xf' : '-xzf',
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
    return installedBinary;
  }

  /// Cria (ou troca) o symlink `dovetail` em [binDir] apontando para o
  /// binário instalado, e avisa quando o diretório está fora do PATH.
  Link linkBin() {
    Directory(binDir).createSync(recursive: true);
    final Link link = Link(
      _context.join(binDir, _isWindows ? 'dovetail.exe' : 'dovetail'),
    );
    if (link.existsSync()) {
      link.deleteSync();
    }
    link.createSync(installedBinary);

    final List<String> path = (_environment['PATH'] ?? '').split(
      _isWindows ? ';' : ':',
    );
    if (!path.contains(binDir)) {
      stdout.writeln('  note: $binDir is not in PATH');
    }
    return link;
  }
}
