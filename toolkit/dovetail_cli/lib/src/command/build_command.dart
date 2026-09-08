import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/src/build/build_defines.dart';
import 'package:dovetail_cli/src/build/flutter_build.dart';
import 'package:dovetail_cli/src/command/doctor_command.dart';
import 'package:dovetail_cli/src/config/config_locator.dart';
import 'package:dovetail_cli/src/config/dovetail_config.dart';
import 'package:dovetail_cli/src/config/pubspec_version.dart';
import 'package:dovetail_process_runner/dovetail_process_runner.dart';

final class BuildCommand extends Command<int> {
  BuildCommand() {
    argParser
      ..addOption('root', help: 'the project directory; defaults to the cwd')
      ..addOption(
        'target',
        allowed: knownTargets,
        help: 'defaults to every declared target this host can build',
      )
      ..addFlag('release', defaultsTo: true)
      ..addOption('flutter', defaultsTo: 'flutter')
      ..addMultiOption('flutter-arg', help: 'passed through, repeatable');
  }

  @override
  String get name => 'build';

  @override
  String get description =>
      'Builds the Flutter desktop app this host can build.';

  @override
  Future<int> run() async {
    final String? root = argResults?.option('root');
    final String host = hostTarget();
    final List<String> targets = _targets(host, root);

    // Nada a construir aqui e um resultado, e tem de ser DITO.
    //
    // Com um `dovetail.yaml` valido cujos `targets:` nao incluem o host, a
    // lista vinha vazia, o `for` nao tinha corpo, e o comando saia 0 com ZERO
    // bytes de saida — um build bem-sucedido que nunca aconteceu. Numa matriz
    // de CI isso e um runner sem trabalho, e sair 0 esta certo; o defeito e o
    // silencio, porque quem le "exit 0" depois de `dovetail build` entende
    // que existe um artefato.
    if (targets.isEmpty) {
      stdout.writeln(
        'nothing to build on $host: dovetail.yaml declares no target for this '
        'host. That is a runner whose part of the matrix lives elsewhere, not '
        'an error — but no artefact was produced here.',
      );
      return 0;
    }

    for (final String target in targets) {
      FlutterBuild.refuseCrossCompile(target, host);
    }

    // O que o yaml decide entra no binario aqui, e e dito: a chave publica
    // que o app vai confiar e o endpoint que vai consultar sao os mesmos que o
    // release assina e o probe verifica. Sem dovetail.yaml, nada e embutido e
    // o app fica com os padroes que traz no codigo.
    final Map<String, String> defines = _defines(root);
    for (final String line in BuildDefines.describe(defines)) {
      stdout.writeln('define   $line');
    }
    final DovetailConfig? config = ConfigLocator.load(from: root);
    if (config?.update != null && config!.update!.publicKey == null) {
      // Dito, nao omitido: um build verde que embutiu chave nenhuma e um app
      // que confia no padrao do codigo, seja ele qual for.
      stdout.writeln(
        'define   ${BuildDefines.publicKey}=<not embedded: update.public-key '
        'is not declared; the app keeps the default in its code>',
      );
    }

    for (final String target in targets) {
      stdout.writeln('building $target');
      // Ao vivo: o `flutter build` leva minutos, e um comando que so fala no
      // fim nao se distingue de um travado. O runner repassa cada pedaco
      // conforme chega, entao nada e reimpresso depois.
      final ProcessOutcome built = await SystemProcessRunner.echoing.run(
        argResults!.option('flutter')!,
        FlutterBuild.argumentsFor(
          target,
          release: argResults!.flag('release'),
          defines: defines,
          extra: argResults!.multiOption('flutter-arg'),
        ),
        workingDirectory: root,
      );

      if (!built.succeeded) {
        return built.exitCode;
      }
      stdout.writeln('output   ${FlutterBuild.outputFor[target]}');
    }

    return 0;
  }

  Map<String, String> _defines(String? root) {
    final DovetailConfig? config = ConfigLocator.load(from: root);
    if (config == null) {
      return const <String, String>{};
    }
    String? version;
    try {
      version = PubspecVersion.read(root ?? Directory.current.path);
    } on Object catch (_) {
      version = null;
    }
    return BuildDefines.of(config: config, appVersion: version);
  }

  List<String> _targets(String host, String? root) {
    final String? given = argResults?.option('target');
    if (given != null) {
      return <String>[given];
    }

    final DovetailConfig? config = ConfigLocator.load(from: root);
    if (config == null) {
      return <String>[host];
    }

    final Set<String> declared = <String>{
      for (final String key in config.targets)
        FlutterBuild.hostFor[_osOf(key)] ?? _osOf(key),
    };
    return declared.contains(host) ? <String>[host] : <String>[];
  }

  static String _osOf(String platformKey) {
    final String os = platformKey.split('-').first;
    return os == 'darwin' ? 'macos' : os;
  }
}
