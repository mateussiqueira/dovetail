import 'dart:io';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/macos/bundle_architectures.dart';
import 'package:dovetail_bundler/src/macos/launch_daemon.dart';
import 'package:dovetail_bundler/src/macos/minimum_system_version.dart';
import 'package:dovetail_bundler/src/macos/service_scripts.dart';
import 'package:dovetail_bundler/src/spec/bundle_spec.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';
import 'package:dovetail_process_runner/dovetail_process_runner.dart';
import 'package:path/path.dart' as p;

/// O irmao do `DmgBundler` para o que o dmg nao sabe instalar.
///
/// O dmg monta uma imagem e o usuario arrasta o `.app`; ele nao roda script
/// privilegiado, entao nao instala daemon. O `.pkg` roda um `postinstall` como
/// root, e e por isso que ele existe — a mesma assimetria que o `.deb` e o
/// `.rpm` fecham no Linux.
///
/// O payload e o `.app`, instalado em `/Applications`. O daemon que a rota
/// `system` declara viaja DENTRO do bundle (o `build` o embarca) e o
/// `postinstall` o copia para `/Library/PrivilegedHelperTools`: e a mesma
/// ordem do Linux, em que o pacote leva o helper e o script de pos-instalacao
/// o poe no lugar certo.
final class PkgBundler {
  const PkgBundler({
    required this.runner,
    this.pkgbuild = 'pkgbuild',
    this.productbuild = 'productbuild',
    this.requiredArchitectures = const <TargetArch>{},
    this.daemon,
    this.scripts,
  });

  final ProcessRunner runner;
  final String pkgbuild;
  final String productbuild;
  final Set<TargetArch> requiredArchitectures;

  /// O daemon do sistema, quando a rota `system` foi declarada. Nulo num
  /// produto sem componente privilegiado — e entao o pkg e so o `.app`.
  final LaunchDaemon? daemon;

  /// Os scripts que instalam e removem o daemon. Vem junto com [daemon] ou
  /// nao vem.
  final MacosServiceScripts? scripts;

  /// Onde o `.app` aterrissa. O nome e o do produto, o mesmo que o usuario le
  /// no Finder, e e o caminho que o `postinstall` procura ao copiar o helper —
  /// os dois saem daqui, e e por isso que [bundle] recusa um par que discorde.
  static String installLocationFor(BundleSpec spec) =>
      '/Applications/${spec.productName}.app';

  String fileNameFor(BundleSpec spec) {
    final String suffix = switch (requiredArchitectures.length) {
      0 => '',
      1 => '_${requiredArchitectures.single.apple}',
      _ => '_universal',
    };
    return '${spec.mainBinaryName}_${spec.version.semantic}$suffix.pkg';
  }

  List<String> pkgBuildArguments({
    required BundleSpec spec,
    required String componentPath,
    String? scriptsDirectory,
  }) => <String>[
    '--root',
    spec.appDirectory,
    '--identifier',
    spec.identifier,
    '--version',
    spec.version.semantic,
    '--install-location',
    installLocationFor(spec),
    if (scriptsDirectory != null) ...<String>['--scripts', scriptsDirectory],
    componentPath,
  ];

  List<String> productBuildArguments({
    required String componentPath,
    required String destination,
  }) => <String>['--package', componentPath, destination];

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
            'A pkg installs the bundle itself, at an install location of its '
            'own. Point app-dir at the .app, not the directory above it.',
      );
    }

    if (spec.extraFiles.isNotEmpty) {
      throw BundleFailure(
        'a pkg was given ${spec.extraFiles.length} staged file(s), and its '
        'payload is the .app.',
        remedy:
            'pkgbuild puts --root at --install-location, and the root here is '
            'the bundle. Anything the application needs belongs inside the '
            'bundle before it is wrapped and before it is signed, because the '
            'bundle seal covers it.',
      );
    }

    _refuseHalfConfiguredService(spec);

    if (requiredArchitectures.isNotEmpty) {
      BundleArchitectures.enforce(
        bundlePath: spec.appDirectory,
        required_: requiredArchitectures,
      );
    }

    // Antes do pkgbuild, pelo mesmo motivo do dmg: um pacote que existe e um
    // pacote que alguem instala, e o piso que ele carrega e o que impede uma
    // maquina velha de abrir um binario que nao roda.
    MinimumSystemVersion.enforce(
      bundlePath: spec.appDirectory,
      declared: spec.minimumSystemVersion,
    );

    Directory(spec.outputDirectory).createSync(recursive: true);
    final String destination = p.join(spec.outputDirectory, fileNameFor(spec));

    // O temporario guarda o pkg de componente e o diretorio de scripts: o
    // pkgbuild escreve o componente, o productbuild o embrulha, e so o segundo
    // e o arquivo que o usuario baixa.
    final Directory scratch = Directory.systemTemp.createTempSync(
      'dovetail_pkg',
    );
    try {
      final String component = p.join(scratch.path, 'component.pkg');
      String? scriptsDirectory;
      if (scripts != null) {
        scriptsDirectory = p.join(scratch.path, 'scripts');
        Directory(scriptsDirectory).createSync(recursive: true);
        // So o postinstall: o pkgbuild nao conhece script de desinstalacao, e
        // um arquivo chamado uninstall aqui dentro viajaria no pacote sem
        // nunca ser executado. Quem desfaz e o que o postinstall escreve no
        // disco, derivado da mesma configuracao.
        await _writeScript(
          p.join(scriptsDirectory, _postinstallName),
          scripts!.postinstall,
        );
      }

      await _run(
        pkgbuild,
        pkgBuildArguments(
          spec: spec,
          componentPath: component,
          scriptsDirectory: scriptsDirectory,
        ),
        name: 'pkgbuild',
      );
      if (!File(component).existsSync()) {
        throw const BundleFailure(
          'pkgbuild reported success but the component package is not there.',
        );
      }

      await _run(
        productbuild,
        productBuildArguments(
          componentPath: component,
          destination: destination,
        ),
        name: 'productbuild',
      );
    } finally {
      scratch.deleteSync(recursive: true);
    }

    if (!File(destination).existsSync()) {
      throw BundleFailure(
        'productbuild reported success but ${fileNameFor(spec)} is not there.',
      );
    }

    return destination;
  }

  /// Um daemon sem scripts nao e carregado por ninguem; scripts sem daemon
  /// escrevem um plist para um binario que o pacote nao instalou. O `.deb`
  /// recusa os dois casos pela mesma razao, e aqui ela vale igual.
  void _refuseHalfConfiguredService(BundleSpec spec) {
    if (daemon == null && scripts == null) {
      return;
    }
    if (daemon == null || scripts == null) {
      throw const BundleFailure(
        'a daemon without a postinstall, or scripts without a daemon.',
        remedy:
            'A daemon nothing loads never starts, and a plist written for a '
            'binary the package did not install fails on every install. Give '
            'both or neither.',
      );
    }
    if (scripts!.daemon.label != daemon!.label) {
      throw BundleFailure(
        'the scripts load "${scripts!.daemon.label}" but the package installs '
        '"${daemon!.label}".',
        remedy: 'They have to name the same label.',
      );
    }
    if (scripts!.applicationPath != installLocationFor(spec)) {
      throw BundleFailure(
        'the scripts read the helper out of "${scripts!.applicationPath}", '
        'and the package installs the app at "${installLocationFor(spec)}".',
        remedy:
            'The postinstall runs after the payload lands, so it has to look '
            'where the payload put the bundle. A mismatch installs the app and '
            'then fails to find the helper inside it.',
      );
    }

    final String helper = p.join(
      spec.appDirectory,
      LaunchDaemon.programPathInBundle(daemon!.program),
    );
    if (!File(helper).existsSync()) {
      throw BundleFailure(
        'the daemon "${daemon!.label}" names '
        '"${LaunchDaemon.programPathInBundle(daemon!.program)}", and there is '
        'no file there.',
        remedy:
            'The postinstall copies that path out of the bundle, so the '
            'install would succeed and the daemon would never start. Build the '
            'helper into the .app, or declare where it really is.',
      );
    }
  }

  Future<void> _run(
    String executable,
    List<String> arguments, {
    required String name,
  }) async {
    final ProcessOutcome outcome = await runner.run(executable, arguments);
    if (outcome.succeeded) {
      return;
    }
    throw BundleFailure(
      '$name failed with exit code ${outcome.exitCode}.',
      remedy: outcome.stderr.trim().isEmpty
          ? outcome.stdout.trim()
          : outcome.stderr.trim(),
    );
  }

  /// O pkgbuild copia o modo do arquivo, entao o postinstall tem de estar
  /// executavel no disco antes de ele rodar — um script que o instalador nao
  /// consegue executar aborta a instalacao inteira.
  Future<void> _writeScript(String path, String body) async {
    File(path).writeAsStringSync(body);
    await _run('chmod', <String>['0755', path], name: 'chmod');
  }

  static const String _postinstallName = 'postinstall';
}
