import 'dart:io';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/macos/bundle_architectures.dart';
import 'package:dovetail_bundler/src/macos/minimum_system_version.dart';
import 'package:dovetail_bundler/src/spec/bundle_spec.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';
import 'package:path/path.dart' as p;
import 'package:dovetail_process_runner/dovetail_process_runner.dart';

/// O artefato que o UPDATER instala: o `.app` já assinado, em `tar.gz`, com o
/// bundle na raiz do arquivo — exatamente o que `MacosInstaller` extrai e
/// troca no lugar. O `.dmg` é para a primeira instalação, pela mão do usuário;
/// o updater não monta imagem de disco.
///
/// Sem este arquivo o manifesto apontava para o dmg, e a primeira atualização
/// automática morria em "could not extract the update archive" — em toda
/// máquina, depois de baixar e verificar 33 MB com sucesso. O `ship` produz os
/// dois: o dmg para a página de download, este para o manifesto.
///
/// Não há assinatura sobre o tar: o que se assina é o `.app` lá dentro
/// (inside out, no passo anterior) e o que se verifica é a assinatura minisign
/// do manifesto sobre os bytes do arquivo. O Gatekeeper não avalia o `.app`
/// que o updater escreve, porque ele não carrega o atributo de quarentena que
/// um download de navegador teria.
final class AppArchiveBundler {
  const AppArchiveBundler({
    required this.runner,
    this.tar = 'tar',
    this.requiredArchitectures = const <TargetArch>{},
  });

  final ProcessRunner runner;
  final String tar;
  final Set<TargetArch> requiredArchitectures;

  /// `-C <pasta do .app> <nome do .app>`: o bundle fica na raiz do arquivo,
  /// que é onde o instalador o procura.
  List<String> argumentsFor(BundleSpec spec, String destination) => <String>[
    '-czf',
    destination,
    '-C',
    p.dirname(spec.appDirectory),
    p.basename(spec.appDirectory),
  ];

  String fileNameFor(BundleSpec spec) {
    final String suffix = switch (requiredArchitectures.length) {
      0 => '',
      1 => '_${requiredArchitectures.single.apple}',
      _ => '_universal',
    };
    return '${spec.mainBinaryName}_${spec.version.semantic}$suffix.app.tar.gz';
  }

  Future<String> bundle(BundleSpec spec) async {
    final Directory app = Directory(spec.appDirectory);
    if (!app.existsSync()) {
      throw BundleFailure(
        'the built application is not at ${spec.appDirectory}.',
        remedy: 'Run flutter build macos --release first.',
      );
    }
    if (p.extension(spec.appDirectory) != '.app') {
      throw BundleFailure(
        '${spec.appDirectory} is not an .app bundle.',
        remedy:
            'The archive carries the bundle, not the directory above it. '
            'Point app-dir at the .app itself.',
      );
    }
    if (spec.extraFiles.isNotEmpty) {
      throw BundleFailure(
        'the update archive was given ${spec.extraFiles.length} staged '
        'file(s), and the installer only looks for the .app.',
        remedy:
            'Anything the application needs belongs inside the bundle before '
            'it is signed, because the bundle seal covers it.',
      );
    }

    if (requiredArchitectures.isNotEmpty) {
      BundleArchitectures.enforce(
        bundlePath: spec.appDirectory,
        required_: requiredArchitectures,
      );
    }
    MinimumSystemVersion.enforce(
      bundlePath: spec.appDirectory,
      declared: spec.minimumSystemVersion,
    );

    Directory(spec.outputDirectory).createSync(recursive: true);
    final String destination = p.join(spec.outputDirectory, fileNameFor(spec));

    // COPYFILE_DISABLE: o tar do macOS guarda atributos estendidos como
    // entradas `._*` (AppleDouble) por padrão, que o tar de extração do
    // instalador recria como arquivos soltos dentro do bundle — e um arquivo
    // a mais dentro de um bundle assinado quebra o selo.
    final ProcessOutcome outcome = await runner.run(
      tar,
      argumentsFor(spec, destination),
      environment: const <String, String>{'COPYFILE_DISABLE': '1'},
    );
    if (!outcome.succeeded) {
      throw BundleFailure(
        'tar failed with exit code ${outcome.exitCode}.',
        remedy: outcome.stderr.trim().isEmpty
            ? outcome.stdout.trim()
            : outcome.stderr.trim(),
      );
    }
    if (!File(destination).existsSync()) {
      throw BundleFailure(
        'tar reported success but ${fileNameFor(spec)} is not there.',
      );
    }
    return destination;
  }
}
