import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/macos/launch_daemon.dart';

/// O que o `.pkg` roda como root — o irmao de `ServiceScripts` no macOS.
///
/// O `postinstall` copia o helper para fora do bundle, escreve o property list
/// e carrega o daemon com `launchctl bootstrap`. O macOS nao tem script de
/// desinstalacao de pacote, entao o `uninstall` e escrito no disco pelo
/// proprio `postinstall`: quem desfaz o servico e um arquivo derivado da mesma
/// configuracao que o instalou, e nao um caminho que alguem manteve em passo.
///
/// Nenhum caminho entra no script como variavel de shell. Tudo e literal,
/// resolvido aqui a partir da configuracao: uma variavel a mais e uma chance a
/// mais de o valor e o caminho discordarem em silencio.
final class MacosServiceScripts {
  MacosServiceScripts({
    required this.daemon,
    required this.identifier,
    required this.applicationPath,
    this.purgePaths = const <String>[],
  }) {
    if (!_identifierPattern.hasMatch(identifier)) {
      throw BundleFailure(
        'the service is installed under "$identifier", which is not a '
        'reverse-domain name.',
        remedy:
            'The uninstaller path and the receipt `pkgutil --forget` forgets '
            'are both derived from it.',
      );
    }
    if (!applicationPath.startsWith('/') || !applicationPath.endsWith('.app')) {
      throw BundleFailure(
        'the application path "$applicationPath" is not an absolute .app '
        'path.',
        remedy:
            'The postinstall copies the helper out of the INSTALLED bundle, so '
            'it has to name where the pkg put it.',
      );
    }
    if (applicationPath.contains("'")) {
      throw BundleFailure(
        'the application path "$applicationPath" carries a single quote.',
        remedy:
            'The scripts name it inside single quotes, and the quote would '
            'end the string and leave the rest of the path to the shell.',
      );
    }

    for (final String path in purgePaths) {
      if (!path.startsWith('/')) {
        throw BundleFailure(
          'the purge path "$path" is not absolute.',
          remedy:
              'These paths are removed by rm -rf during uninstall. A relative '
              'one would delete whatever sits under the working directory of '
              'the uninstaller.',
        );
      }
      if (path.contains(' ')) {
        throw BundleFailure(
          'the purge path "$path" contains a space.',
          remedy:
              'A path with a space is one nobody can read back, and this is '
              'the list a root script deletes from.',
        );
      }
      if (path.split('/').where((String s) => s.isNotEmpty).length < 2) {
        throw BundleFailure(
          'the purge path "$path" is too close to the root.',
          remedy: 'rm -rf on a top-level directory is not a purge.',
        );
      }
      if (path.contains("'")) {
        throw BundleFailure(
          'the purge path "$path" carries a single quote.',
          remedy:
              'The uninstaller names it inside single quotes, and the quote '
              'would end the string and leave the rest of the path to the '
              'shell.',
        );
      }
    }
  }

  final LaunchDaemon daemon;
  final String identifier;
  final String applicationPath;
  final List<String> purgePaths;

  /// 0755 — o modo que o `pkgbuild` preserva; um script que o instalador nao
  /// consegue executar aborta a instalacao inteira.
  static const int scriptMode = 0x1ED;

  static const String _applicationSupportDirectory =
      '/Library/Application Support';

  static const String _plistDelimiter = 'DOVETAIL_PLIST';

  static const String _uninstallDelimiter = 'DOVETAIL_UNINSTALL';

  /// Onde fica o desinstalador. Sai do `identifier`, como todo caminho aqui.
  String get uninstallDirectory => '$_applicationSupportDirectory/$identifier';

  String get uninstallerPath => '$uninstallDirectory/uninstall';

  /// O helper no disco, ja fora do `.app` — o que o plist aponta.
  String get installedExecutablePath => daemon.installedExecutablePath;

  String get postinstall => <String>[
    '#!/bin/sh',
    'set -e',
    '',
    '# O pkg instala POR CIMA: um label ja carregado faz o bootstrap falhar, e',
    '# uma reinstalacao e o caso normal, nao a excecao. O bootout antes e o',
    '# que torna o passo repetivel.',
    'launchctl bootout "system/${daemon.label}" >/dev/null 2>&1 || true',
    '',
    "install -d -o root -g wheel -m 0755 '${LaunchDaemon.installedDirectory}'",
    'install -o root -g wheel -m 0544 '
        "'$applicationPath/${LaunchDaemon.programPathInBundle(daemon.program)}' "
        "'$installedExecutablePath'",
    '',
    // O plist e escrito aqui, e nao viajado no payload, porque o dono e o
    // modo que o launchd exige sao parte do que este passo tem de garantir —
    // e porque o plist do sistema aponta para o caminho JA instalado.
    "cat > '${daemon.installedPropertyListPath}' <<'$_plistDelimiter'",
    ...daemon.render().trimRight().split('\n'),
    _plistDelimiter,
    "chown root:wheel '${daemon.installedPropertyListPath}'",
    "chmod 0644 '${daemon.installedPropertyListPath}'",
    '',
    '# Sem script de desinstalacao de pkg, o desinstalador e um ARQUIVO. Ele',
    '# e escrito daqui para que instalacao e remocao nao possam divergir de',
    '# caminho.',
    "install -d -o root -g wheel -m 0755 '$uninstallDirectory'",
    "cat > '$uninstallerPath' <<'$_uninstallDelimiter'",
    ...uninstall.trimRight().split('\n'),
    _uninstallDelimiter,
    "chown root:wheel '$uninstallerPath'",
    "chmod 0755 '$uninstallerPath'",
    '',
    // O launchd derruba o label antigo de forma assincrona, e um bootstrap
    // imediato encontra o servico ainda registrado. Reinstalar por cima e o
    // caso normal, entao o passo insiste.
    'for _dovetail_attempt in 1 2 3 4 5; do',
    "\tlaunchctl bootstrap system '${daemon.installedPropertyListPath}' "
        '&& exit 0',
    '\tsleep 1',
    'done',
    '',
    // A ultima tentativa e a que decide, e ela larga o plist antes de falhar:
    // o scan do launchd le tudo o que esta em /Library/LaunchDaemons no
    // proximo boot, entao um plist deixado para tras por uma instalacao que
    // ABORTOU volta como daemon rodando. O binario e o desinstalador ficam,
    // que e o que permite limpar o resto.
    'if ! launchctl bootstrap system '
        "'${daemon.installedPropertyListPath}'; then",
    "\trm -f '${daemon.installedPropertyListPath}'",
    '\texit 1',
    'fi',
    '',
    'exit 0',
    '',
  ].join('\n');

  String get uninstall => <String>[
    '#!/bin/sh',
    'set -e',
    '',
    '# A ordem inversa da instalacao: o launchd primeiro, senao o daemon fica',
    '# carregado apontando para um binario que ja nao existe.',
    'launchctl bootout "system/${daemon.label}" >/dev/null 2>&1 || true',
    "rm -f '${daemon.installedPropertyListPath}'",
    "rm -f '$installedExecutablePath'",
    '',
    // `/Library/PrivilegedHelperTools` e compartilhado por todos os produtos
    // que instalam helper: apagar o diretorio e apagar o dos outros. So o
    // binario deste produto sai.
    //
    // O recibo e o registro que faz o macOS achar que este pacote ainda esta
    // instalado — e o proximo `.pkg` ser tratado como upgrade. Desinstalar sem
    // esquece-lo deixa um pacote fantasma no banco de recibos, que e a sobra
    // que nao aparece num `ls`.
    "pkgutil --forget '$identifier' >/dev/null 2>&1 || true",
    if (purgePaths.isNotEmpty) ...<String>[
      '',
      '# O que a instalacao nao criou mas o produto escreveu, e so aqui: um',
      '# caminho nao declarado nunca e apagado por este script.',
      for (final String path in purgePaths) "rm -rf '$path'",
    ],
    '',
    '# O desinstalador sai junto: um script de desinstalacao que fica no disco',
    '# e exatamente a sobra que ele veio remover.',
    "rm -f '$uninstallerPath'",
    "rmdir '$uninstallDirectory' >/dev/null 2>&1 || true",
    '',
    'exit 0',
    '',
  ].join('\n');

  static final RegExp _identifierPattern = RegExp(
    r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$',
  );
}
