import 'dart:io';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/macos/launch_daemon.dart';
import 'package:dovetail_bundler/src/xml_text.dart';
import 'package:path/path.dart' as p;

/// Põe o componente privilegiado DENTRO do `.app`, que é o único lugar de onde
/// ele pode chegar a uma máquina por um `.dmg`.
///
/// O que o `.dmg` entrega é o bundle e nada mais: não há `postinstall`, não há
/// ninguém escrevendo em `/Library/LaunchDaemons`. Um produto com daemon que
/// não o embarca sai com um aplicativo completo e sem o processo que faz o
/// trabalho — e a tela diz "não instalado" sobre algo que nunca foi empacotado.
///
/// Duas decisões que parecem detalhe e não são:
///
/// 1. O `Label` do plist e o NOME do arquivo têm de coincidir. O
///    `SMAppService.daemon(plistName:)` resolve o daemon pelo nome do arquivo e
///    compara com o rótulo lá dentro; divergindo, ele registra e nunca casa.
/// 2. `BundleProgram` é RELATIVO à raiz do bundle. Um caminho absoluto aponta
///    para a máquina que construiu, e o daemon não sobe na máquina que instala.
final class DaemonEmbedder {
  const DaemonEmbedder();

  /// Onde o binário mora dentro do bundle, a partir da raiz dele.
  static String programPathFor(String program) => 'Contents/MacOS/$program';

  /// O property list que o `SMAppService` procura.
  ///
  /// `RunAtLoad` e `KeepAlive` não são enfeite num produto com kill switch: um
  /// daemon morto com filtros instalados deixa a máquina sem rede, e ninguém os
  /// remove. `ProcessType Interactive` o mantém fora do estrangulamento que o
  /// launchd aplica a tarefa de fundo — um túnel estrangulado perde handshake.
  static String plistFor({
    required String label,
    required String program,
    List<String> arguments = const <String>[],
  }) {
    _requireEmbeddableProgramName(program);

    // `arguments` e `label` saem do `dovetail.yaml` de quem usa o toolkit e
    // entram em elementos <string>. Interpolados crus, um `&` de um argumento
    // tipo "--mode a&b" fechava o XML antes da hora: o launchd não lê o
    // plist, o daemon não registra, e o sintoma aparece na máquina de quem
    // usa — a classe de recusa sobre a qual ele não pode agir.
    final String embedded = programPathFor(program);
    final StringBuffer args = StringBuffer();
    for (final String argument in arguments) {
      args.writeln('        <string>${XmlText.content(argument)}</string>');
    }

    return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${XmlText.content(label)}</string>
    <key>BundleProgram</key>
    <string>$embedded</string>
    <key>ProgramArguments</key>
    <array>
        <string>$embedded</string>
${args.toString().trimRight()}
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>${XmlText.content(LaunchDaemon.logPathFor(label))}</string>
    <key>StandardErrorPath</key>
    <string>${XmlText.content(LaunchDaemon.logPathFor(label))}</string>
</dict>
</plist>
''';
  }

  /// O `program` não é escapado, é recusado.
  ///
  /// O nome viaja em três lugares: o arquivo dentro de `Contents/MacOS/`, a
  /// chave relativa que `sign --entitlements-for` e o próprio embedder usam
  /// para achá-lo, e o plist. Só o plist decodifica entidades — escapar uma
  /// ocorrência e não as outras transformaria cada consumidor presente e
  /// futuro em alguém obrigado a decodificar antes de abrir o caminho. Um
  /// nome de daemon legítimo não carrega `&`, `<` nem `>`, e a recusa custa
  /// uma frase no yaml; o silêncio custaria um daemon que não registra.
  static void _requireEmbeddableProgramName(String program) {
    if (program.contains('&') ||
        program.contains('<') ||
        program.contains('>')) {
      throw BundleFailure(
        'service.macos.program is "$program", and a program name cannot '
        'carry &, < or >.',
        remedy:
            'The name becomes a file inside Contents/MacOS, a path the '
            'signing step looks up, and a plist entry — only the last of '
            'the three would decode XML entities. Name the binary something '
            'the filesystem, the signer and the plist all agree on.',
      );
    }
  }

  /// Copia o binário e escreve o plist. Idempotente: reescreve os dois.
  ///
  /// Recusa em vez de adivinhar quando o binário não existe. Quem o compila é o
  /// projeto — esta ferramenta não conhece a cadeia de build dele —, e um
  /// bundle montado sem o daemon é exatamente o defeito que este passo fecha.
  void embed({
    required String appDirectory,
    required String binary,
    required String program,
    required String label,
    List<String> arguments = const <String>[],
    bool writePropertyList = true,
  }) {
    // Antes de qualquer cópia: um nome recusado não pode deixar metade de um
    // daemon para trás no bundle.
    _requireEmbeddableProgramName(program);

    final File source = File(binary);
    if (!source.existsSync()) {
      throw BundleFailure(
        'the privileged component is not at $binary.',
        remedy:
            'dovetail embeds the daemon, it does not build it: compile it '
            'first, or point service.macos.binary at what your build '
            'produces. A bundle without it ships an app whose helper never '
            'arrives.',
      );
    }

    final String destination = p.join(
      appDirectory,
      programPathFor(program).replaceAll('/', p.separator),
    );
    Directory(p.dirname(destination)).createSync(recursive: true);
    source.copySync(destination);
    _makeExecutable(destination);

    // `writePropertyList` e falso na rota `system`: o binario viaja no bundle
    // porque e de dentro dele que o postinstall do `.pkg` o copia para
    // `/Library`, mas o plist que vale la e escrito pelo proprio postinstall,
    // com o caminho absoluto ja instalado. O plist EMBUTIDO e da rota
    // `bundled`, que o `SMAppService` procura dentro do app — escreve-lo aqui
    // deixaria no bundle um arquivo que ninguem le, apontando para um
    // `BundleProgram` que nao e o que o daemon do sistema usa.
    if (!writePropertyList) {
      return;
    }

    final File plist = File(
      p.join(
        appDirectory,
        'Contents',
        'Library',
        'LaunchDaemons',
        '$label.plist',
      ),
    );
    plist.parent.createSync(recursive: true);
    plist.writeAsStringSync(
      plistFor(label: label, program: program, arguments: arguments),
    );
  }

  /// A cópia preserva o conteúdo e não o modo. Um daemon sem bit de execução é
  /// recusado pelo launchd com um erro que não diz isso.
  void _makeExecutable(String path) {
    if (Platform.isWindows) {
      return;
    }
    Process.runSync('chmod', <String>['755', path]);
  }
}
