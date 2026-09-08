import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/src/app/app_template.dart';
import 'package:dovetail_cli/src/bridge/bridge_scaffold.dart';
import 'package:dovetail_cli/src/bridge/bridge_template.dart';
import 'package:dovetail_cli/src/config/config_locator.dart';
import 'package:dovetail_cli/src/config/config_template.dart';
import 'package:dovetail_cli/src/config/project_probe.dart';
import 'package:dovetail_cli/src/scaffold/template_renderer.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:dovetail_cli/src/sdk/sdk_overrides.dart';
import 'package:path/path.dart' as p;

/// Scaffolds a dovetail desktop project from the SDK's app template: the
/// clean-arch Flutter tree wired by Weave, the Rust core, the FFI bridge that
/// passes it through, and the two check suites that keep the conventions.
///
/// Unlike [InitCommand], which reads an existing project and writes
/// `dovetail.yaml`, this command creates the project from scratch: a
/// `pubspec.yaml` with the dovetail, weave_di and bridge path dependencies,
/// the template tree under `lib/`, `core/` and `core_bridge/`, and a
/// `dovetail.yaml` with the defaults that `dovetail doctor` expects.
final class NewCommand extends Command<int> {
  NewCommand({this._sdkLocator, Map<String, String>? environment})
    : _environment = environment ?? Platform.environment {
    argParser
      ..addOption(
        'root',
        help: 'directory that will hold the new project; defaults to cwd',
      )
      ..addOption(
        'name',
        help: 'project name (default: inferred from the directory name)',
      )
      ..addOption(
        'identifier',
        help: 'reverse-dns id; defaults to com.example.<name>',
      )
      ..addOption(
        'dovetail-path',
        help:
            'path dependency for the dovetail library in pubspec.yaml; '
            'when omitted, the repo is computed, then the installed SDK',
      )
      ..addOption(
        'weave-path',
        help:
            'path dependency for weave_di; when omitted, the installed SDK. '
            r'Also read from $DOVETAIL_WEAVE_PATH',
      )
      ..addOption(
        'template',
        help:
            'directory with the app template; defaults to the installed SDK, '
            'then the repo (tool/sdk/templates/app)',
      )
      ..addOption(
        'bridge-template',
        help:
            'directory with the bridge template; defaults to the installed '
            'SDK, then the repo. It has to match --template: template and '
            'dovetail_rust_core are one thing',
      )
      ..addFlag(
        'sdk',
        negatable: false,
        help:
            'resolve the runtime from the installed SDK via '
            'pubspec_overrides.yaml, instead of a path in the pubspec',
      )
      ..addFlag(
        'no-create',
        negatable: false,
        help: 'skip flutter create; leave the platform directories empty',
      );
  }

  final SdkLocator? _sdkLocator;
  final Map<String, String> _environment;

  @override
  String get name => 'new';

  @override
  String get description =>
      'Creates a dovetail desktop project: Flutter UI, Rust core and bridge.';

  @override
  Future<int> run() async {
    final String root = argResults?.option('root') ?? Directory.current.path;
    final String? requestedName =
        argResults?.option('name') ??
        (argResults?.rest.isNotEmpty == true ? argResults!.rest.first : null);
    final String? identifier = argResults?.option('identifier');
    final String? dovetailPath = argResults?.option('dovetail-path');

    final String projectName = requestedName ?? p.basename(root);
    _validateName(projectName);

    final String projectRoot = p.join(root, projectName);
    if (Directory(projectRoot).existsSync()) {
      throw UsageException(
        '$projectRoot already exists.',
        'Remove it or choose a different name.\n\n$usage',
      );
    }

    final bool useSdk = argResults?.flag('sdk') ?? false;

    // O SDK é localizado antes de qualquer arquivo ser escrito: um --sdk sem
    // SDK instalado sai sem deixar o scaffold pela metade.
    final SdkInstall? sdk = useSdk
        ? SdkOverrides.requireSdk(_sdkLocator ?? SdkLocator(), usage)
        : null;

    // As quatro coisas que o scaffold aponta — barril, weave_di, template do
    // app e template do bridge — sao localizadas ANTES de qualquer byte ser
    // escrito, e recusadas JUNTAS. Uma por vez, cada corrida mostrava uma
    // falta, a pessoa consertava, e a proxima corrida mostrava a seguinte:
    // quatro rodadas para descobrir o que uma so poderia ter dito.
    final List<(String, String)> refusals = <(String, String)>[];

    String? resolvedPath;
    if (useSdk) {
      // O override resolve o runtime do SDK; o path do pubspec é um
      // placeholder que o pubspec_overrides.yaml sombreia (o pub substitui a
      // fonte por completo — provado). Assim o pubspec não carrega path
      // absoluto de máquina.
      resolvedPath = dovetailPath ?? 'toolkit/dovetail';
    } else {
      final String? computed =
          dovetailPath ??
          _defaultDovetailPath(projectRoot) ??
          _sdkPackagePath('dovetail');
      if (computed == null) {
        refusals.add((
          'the dovetail library could not be located from $projectRoot.',
          'A scaffold whose path dependency points nowhere fails on its first '
              'flutter pub get, which is a lie about being set up. Put the new '
              'project inside the dovetail repository (that is where --root '
              'points, not where you run from), pass --dovetail-path <dir with '
              'pubspec.yaml>, or install the SDK (dovetail self-install) so '
              'the scaffold points at it.',
        ));
      }
      resolvedPath = computed;
    }

    // O `weave_di` segue exatamente a mesma regra do barril, e por um motivo
    // que custou caro: ele era uma dependencia `git` com a url
    // `git@weave-di.github.com:` — um alias de SSH que existe no
    // `~/.ssh/config` de uma maquina so. Todo projeto que este comando gerou
    // herdava isso, entao o `flutter pub get` de qualquer outra pessoa morria
    // num host que o DNS nao resolve. O repositorio e privado, entao trocar
    // pela url https tambem nao resolveria para quem esta de fora: o caminho
    // certo e o mesmo dos outros pacotes do runtime — viajar dentro do SDK.
    String? resolvedWeavePath;
    if (useSdk) {
      // Placeholder, como o do barril: o pubspec_overrides.yaml sombreia, e
      // `SdkOverrides.render` ja emite uma linha para cada pacote que o SDK
      // carrega — inclusive este, sem precisar saber o nome dele.
      resolvedWeavePath = 'packages/weave_di';
    } else {
      final String? computedWeave =
          _packageAt(argResults?.option('weave-path')) ??
          _packageAt(_environment['DOVETAIL_WEAVE_PATH']) ??
          _sdkPackagePath('weave_di');
      if (computedWeave == null) {
        refusals.add((
          'weave_di could not be located from $projectRoot.',
          'The template uses it for DI and routing, the repository is '
              'private, and a scaffold whose path dependency points nowhere '
              'fails on its first flutter pub get. Point at a checkout with '
              '--weave-path <dir with pubspec.yaml>, set '
              r'$DOVETAIL_WEAVE_PATH, or install the SDK '
              '(dovetail self-install), which carries it.',
        ));
      }
      resolvedWeavePath = computedWeave;
    }

    // Os templates resolvem como o bridge: explícito, depois o SDK, depois o
    // repo — e os dois têm que existir antes de qualquer byte ser escrito.
    final String? templateRoot = AppTemplate.locate(
      explicit: argResults?.option('template'),
      sdkHome: _sdkLocator?.home,
    );
    if (templateRoot == null) {
      refusals.add((
        'the app template could not be located.',
        'Pass --template <dir with tool/sdk/templates/app>, or install the '
            'SDK (dovetail self-install) so the template ships beside the '
            'runtime.',
      ));
    }
    final BridgeTemplate? bridge = BridgeTemplate.locate(
      explicit: argResults?.option('bridge-template'),
      sdkHome: _sdkLocator?.home,
    );
    if (bridge == null) {
      refusals.add((
        'the bridge template could not be located.',
        'The bridge comes from the same place as the runtime. Pass '
            '--bridge-template <dir with the bridge template>, install the SDK '
            '(dovetail self-install), or put the new project inside the '
            'dovetail repository (that is where --root points, not where you '
            'run from). It has to match --template: template and dovetail_rust_core '
            'are one thing.',
      ));
    }

    // Um `if` so, para o analisador promover os quatro de uma vez: depois
    // dele nenhum e nulo, e `refusals` tem exatamente o que faltou.
    if (resolvedPath == null ||
        resolvedWeavePath == null ||
        templateRoot == null ||
        bridge == null) {
      throw _refuseTogether(refusals);
    }

    final String id = identifier ?? 'com.example.$projectName';

    // scaffold — create the directories and files
    Directory(p.join(projectRoot, 'lib')).createSync(recursive: true);
    Directory(p.join(projectRoot, 'test')).createSync(recursive: true);
    // The probe derives the shipped targets from the platform directories,
    // and the config refuses an empty target list, so each desktop host gets
    // a directory even before `flutter create` fills it in.
    for (final String platform in <String>['macos', 'windows', 'linux']) {
      Directory(p.join(projectRoot, platform)).createSync(recursive: true);
    }

    // O bridge primeiro: o template do app carrega o overlay que o completa
    // (o repasse de exemplo e o portão de cobertura com o piso do scaffold),
    // e a renderização do app sobrescreve o que o template entregou.
    BridgeScaffold(template: bridge).render(
      out: p.join(projectRoot, 'core_bridge'),
      name: 'core_bridge',
      coreCrateName: '${projectName}_core',
      // O Cargo resolve path relativo ao MANIFEST (core_bridge/rust/), não ao
      // pacote — dois níveis acima é o core/ do projeto.
      corePath: '../../core',
    );

    TemplateRenderer.renderTree(
      from: Directory(templateRoot),
      to: Directory(projectRoot),
      values: <String, String>{
        'name': projectName,
        'camel_name': _toPascalCase(projectName),
      },
    );

    _writePubspec(projectRoot, projectName, resolvedPath, resolvedWeavePath);
    _writeDovetailYaml(projectRoot, id, projectName);
    if (sdk != null) {
      _writeSdkOverrides(projectRoot, sdk);
    }

    if (!(argResults?.flag('no-create') ?? false)) {
      _fillPlatforms(projectRoot);
    }

    stdout
      ..writeln('wrote $projectRoot')
      ..writeln()
      ..writeln('next steps:')
      // O que a pessoa vai digitar. Com `--root` noutro lugar, `basename`
      // imprimia `cd demo` para um diretorio que nao esta aqui — a primeira
      // linha do "next steps" mandava para o lugar errado. Relativo quando o
      // projeto esta debaixo do cwd (o caso comum, e `cd demo` continua sendo
      // `cd demo`); absoluto quando nao esta, porque um `../../../../var/...`
      // e correto e ilegivel.
      ..writeln('  cd ${_cdTarget(projectRoot)}')
      ..writeln('  flutter pub get')
      ..writeln('  make codegen        # regenera a ponte quando o núcleo muda')
      ..writeln('  make quality        # as duas suites de checks')
      ..writeln('  flutter test')
      ..writeln('  dovetail doctor');
    return 0;
  }

  void _writeSdkOverrides(String projectRoot, SdkInstall sdk) {
    final File target = File(p.join(projectRoot, SdkOverrides.fileName));
    target.writeAsStringSync(SdkOverrides.render(sdk));
    stdout
      ..writeln('wrote ${target.path}')
      ..writeln('  the runtime resolves from the SDK at ${sdk.packagesDir}');
  }

  /// Runs `flutter create --platforms=macos,windows,linux .` to fill in the
  /// platform directories the scaffold leaves empty. It is a best-effort
  /// fill-in, not a gate: the scaffold is already a valid project (the path
  /// dependency was verified before any file was written, and the empty
  /// directories satisfy the probe), so a missing flutter or a failed create
  /// prints the exact command to run by hand and the scaffold stands. Failing
  /// here would make `new` non-hermetic on hosts without flutter, and would
  /// discard a project that is still usable.
  void _fillPlatforms(String projectRoot) {
    if (Process.runSync('which', <String>['flutter']).exitCode != 0) {
      stdout.writeln(
        'flutter not found — run: flutter create '
        '--platforms=macos,windows,linux ${p.basename(projectRoot)}',
      );
      return;
    }
    final ProcessResult created = Process.runSync('flutter', <String>[
      'create',
      '--platforms=macos,windows,linux',
      '.',
    ], workingDirectory: projectRoot);
    if (created.exitCode != 0) {
      final List<String> lines = '${created.stdout}${created.stderr}'
          .split('\n')
          .where((String line) => line.trim().isNotEmpty)
          .toList();
      stdout
        ..writeln(
          'flutter create failed (exit ${created.exitCode}); the scaffold is '
          'intact — fill the platforms in by hand:',
        )
        ..writeln('  flutter create --platforms=macos,windows,linux .');
      if (lines.isNotEmpty) {
        final int from = lines.length - 8 < 0 ? 0 : lines.length - 8;
        stdout.writeln('  …${lines.sublist(from).join('\n  …')}');
      }
    }
  }

  static final RegExp _namePattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$');

  /// Uma recusa so, com tudo o que faltou. Com uma falta e a mensagem de
  /// sempre; com mais, a manchete conta e o corpo lista cada uma com a sua
  /// saida — para uma corrida mostrar todos os consertos, nao um por corrida.
  UsageException _refuseTogether(List<(String, String)> refusals) {
    if (refusals.length == 1) {
      final (String problem, String remedy) = refusals.single;
      return UsageException(problem, '$remedy\n\n$usage');
    }
    final StringBuffer body = StringBuffer();
    for (final (String problem, String remedy) in refusals) {
      body
        ..writeln(problem)
        ..writeln('  $remedy')
        ..writeln();
    }
    return UsageException(
      '${refusals.length} things this scaffold would point at could not be '
          'located.',
      'Listed together so one run shows every fix, not one per run.\n\n'
          '${body.toString().trimRight()}\n\n$usage',
    );
  }

  void _validateName(String name) {
    if (!_namePattern.hasMatch(name)) {
      throw UsageException(
        '"$name" is not a valid project name.',
        'A project name must start with a letter and contain only '
            'letters, digits and underscores.\n\n$usage',
      );
    }
  }

  /// Resolves where the dovetail library lives, in this order: the repo,
  /// when the command runs via `dart run` inside it (the script sits in
  /// `toolkit/dovetail_cli/bin/`, so the scaffold's relative path points
  /// somewhere real), and then the installed SDK — a compiled binary has no
  /// repo to point at, but the SDK it ships beside carries the runtime.
  static String? _defaultDovetailPath(String projectRoot) {
    final String viaScript = p.normalize(
      p.join(
        projectRoot,
        '..',
        '..',
        'toolkit',
        'dovetail',
        'lib',
        'dovetail.dart',
      ),
    );
    if (File(viaScript).existsSync()) {
      final String packageRoot = p.dirname(p.dirname(viaScript));
      return p.normalize(p.relative(packageRoot, from: projectRoot));
    }
    return null;
  }

  static String _cdTarget(String projectRoot) {
    final String here = Directory.current.path;
    return p.isWithin(here, projectRoot)
        ? p.relative(projectRoot)
        : projectRoot;
  }

  /// [candidate] se ele for mesmo um pacote, e `null` caso contrário.
  ///
  /// Duas armadilhas, e as duas ja morderam. Uma variavel de ambiente exportada
  /// vazia (`DOVETAIL_WEAVE_PATH=`) chega como `''`, que nao e null e passaria
  /// por um `??`: o scaffold sairia com `path: ""`. E um caminho digitado
  /// errado so falharia no `flutter pub get` do consumidor — tarde demais,
  /// porque a promessa deste comando e justamente que o scaffold resolve.
  static String? _packageAt(String? candidate) {
    final String path = candidate?.trim() ?? '';
    if (path.isEmpty) {
      return null;
    }
    if (!File(p.join(path, 'pubspec.yaml')).existsSync()) {
      return null;
    }
    return p.normalize(p.absolute(path));
  }

  /// Um pacote do SDK instalado, em caminho absoluto — o gerado pode morar
  /// em qualquer lugar, e o SDK é de quem gerou, não portátil.
  String? _sdkPackagePath(String package) {
    final SdkInstall? sdk = (_sdkLocator ?? SdkLocator()).locate();
    if (sdk == null) {
      return null;
    }
    final String packageRoot = p.join(sdk.packagesDir, package);
    if (!File(p.join(packageRoot, 'pubspec.yaml')).existsSync()) {
      return null;
    }
    return p.normalize(p.absolute(packageRoot));
  }

  void _writePubspec(
    String projectRoot,
    String name,
    String dovetailPath,
    String weavePath,
  ) {
    final File file = File(p.join(projectRoot, 'pubspec.yaml'));
    file.writeAsStringSync('''
name: $name
description: >-
  A dovetail desktop project: Flutter UI, Rust core and bridge.
version: 0.1.0+1
publish_to: none

environment:
  sdk: ^3.12.0
  flutter: ">=3.24.0"

dependencies:
  flutter:
    sdk: flutter
  dovetail:
    path: "${dovetailPath.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"
  core_bridge:
    path: core_bridge
  weave_di:
    path: "${weavePath.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
''');
  }

  void _writeDovetailYaml(String projectRoot, String identifier, String name) {
    final File file = File(p.join(projectRoot, ConfigLocator.fileName));
    file.writeAsStringSync(
      ConfigTemplate.render(ProjectProbe(projectRoot), identifier: identifier),
    );
  }

  static String _toPascalCase(String snake) {
    return snake
        .split('_')
        .map((String w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join();
  }
}
