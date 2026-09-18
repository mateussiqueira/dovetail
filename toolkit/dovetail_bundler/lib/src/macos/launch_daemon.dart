import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/xml_text.dart';

/// O daemon que um instalador rodando como root poe em `/Library` — a rota
/// `system` do macOS.
///
/// Distinto do `DaemonEmbedder`, que e a rota `bundled`: la o daemon viaja
/// DENTRO do `.app`, o `SMAppService` o registra de dentro do bundle, e o
/// plist usa `BundleProgram`, relativo a raiz do bundle. Aqui ele mora FORA do
/// app, em `/Library/PrivilegedHelperTools`, e o `ProgramArguments` do plist e
/// o caminho absoluto ja instalado — o `launchctl` carrega o plist de
/// `/Library/LaunchDaemons`, que nao esta dentro de bundle nenhum.
///
/// O binario NAO e instalado a partir daqui: ele viaja no `.app` (o `build` o
/// embarca) e o `postinstall` do `.pkg` o copia para o caminho instalado. Esta
/// classe so descreve o destino e o property list que o aponta.
final class LaunchDaemon {
  LaunchDaemon({
    required this.label,
    required this.program,
    this.arguments = const <String>[],
    this.runAtLoad = true,
    this.keepAlive = true,
  }) {
    if (!_labelPattern.hasMatch(label)) {
      throw BundleFailure(
        'the launchd label "$label" is not a reverse-domain name.',
        remedy:
            'launchd names the property list after the label and keys the '
            'daemon by it, so it has to read as com.example.app.something. A '
            'label with a space or a slash is a daemon nothing can address.',
      );
    }
    if (program.trim().isEmpty) {
      throw const BundleFailure(
        'the daemon names an empty program.',
        remedy: 'Give the file name the binary gets inside the bundle.',
      );
    }
    if (program.contains('/')) {
      throw BundleFailure(
        'the daemon program "$program" is a path.',
        remedy:
            'The postinstall copies the binary out of the bundle at a fixed '
            'place, so what goes here is the file NAME, not a path — the '
            'path is derived, not declared.',
      );
    }
    // O nome viaja no plist (que escapa XML) e no script do postinstall, entre
    // quotes simples. Escapar uma ocorrencia e nao as outras obrigaria todo
    // consumidor a decodificar antes de abrir o caminho; um nome legitimo de
    // binario nao carrega `&`, `<`, `>` nem uma quote.
    if (program.contains('&') ||
        program.contains('<') ||
        program.contains('>')) {
      throw BundleFailure(
        'the daemon program "$program" carries a character XML reserves.',
        remedy:
            'The name becomes a file inside the bundle, a path the '
            'postinstall script copies, and a property list entry — only the '
            'last decodes XML entities. Name the binary something the '
            'filesystem, the script and the plist all agree on.',
      );
    }
    if (program.contains("'")) {
      throw BundleFailure(
        'the daemon program "$program" carries a single quote.',
        remedy:
            'The postinstall names it inside single quotes, and the quote '
            'would end the string and leave the rest of the path to the shell.',
      );
    }

    // Sem MachServices o launchd nao tem cliente para quem iniciar o job sob
    // demanda: um daemon que nao sobe no load e nao e mantido vivo fica
    // carregado e nunca roda. O plist que este toolkit escreve nao declara
    // MachServices, entao um dos dois tem de ser verdadeiro.
    if (!runAtLoad && !keepAlive) {
      throw const BundleFailure(
        'the daemon neither runs at load nor is kept alive.',
        remedy:
            'A property list with no MachServices gives launchd no client to '
            'start the job for, so it would install and never connect. Set '
            'run-at-load or keep-alive to true.',
      );
    }
  }

  /// O nome pelo qual o launchd conhece o daemon: vai no `<key>Label</key>` e
  /// no nome do property list.
  final String label;

  /// O nome do binario DENTRO do bundle — o `service.macos.program`.
  final String program;

  /// O que o daemon recebe na linha de comando, depois do proprio caminho.
  final List<String> arguments;

  /// Sobe no boot. O padrao do launchd e nao subir; um helper que so responde
  /// a XPC deixaria isto em false.
  final bool runAtLoad;

  /// Relanca quando o processo morre. Um kill switch que ficou fora do ar e
  /// pior que um que nunca subiu, porque ninguem percebe.
  final bool keepAlive;

  /// Onde os helpers privilegiados moram no macOS.
  static const String installedDirectory = '/Library/PrivilegedHelperTools';

  static const String launchDaemonsDirectory = '/Library/LaunchDaemons';

  /// O caminho do binario dentro do bundle, relativo a raiz dele — a mesma
  /// pasta em que o `DaemonEmbedder` o poe.
  static String programPathInBundle(String program) =>
      'Contents/MacOS/$program';

  String get installedExecutablePath => '$installedDirectory/$label';

  String get installedPropertyListPath =>
      '$launchDaemonsDirectory/$label.plist';

  String render() => <String>[
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    '<plist version="1.0">',
    '<dict>',
    '\t<key>Label</key>',
    '\t<string>${XmlText.content(label)}</string>',
    '\t<key>ProgramArguments</key>',
    '\t<array>',
    '\t\t<string>${XmlText.content(installedExecutablePath)}</string>',
    for (final String argument in arguments)
      '\t\t<string>${XmlText.content(argument)}</string>',
    '\t</array>',
    '\t<key>RunAtLoad</key>',
    runAtLoad ? '\t<true/>' : '\t<false/>',
    if (keepAlive) ...<String>['\t<key>KeepAlive</key>', '\t<true/>'],
    // Tira o daemon do estrangulamento que o launchd aplica a tarefa de fundo:
    // um tunel estrangulado perde handshake.
    '\t<key>ProcessType</key>',
    '\t<string>Interactive</string>',
    '</dict>',
    '</plist>',
    '',
  ].join('\n');

  static final RegExp _labelPattern = RegExp(
    r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$',
  );
}
