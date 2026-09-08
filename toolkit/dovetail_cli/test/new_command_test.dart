import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:dovetail_cli/src/sdk/sdk_locator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

/// The scaffold's path dependency must resolve, or the first `flutter pub
/// get` lies about being set up. Every test that scaffolds passes the real
/// dovetail package from this repository, so the generated pubspec points
/// somewhere real — and the refusal when it cannot is its own test.
void main() {
  late Directory root;
  late Directory sdkHome;
  late CommandRunner<int> runner;

  final String dovetailPath = p.join(repoRoot(), 'toolkit', 'dovetail');

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_new');
    sdkHome = Directory.systemTemp.createTempSync('dovetail_new_sdk');
    runner = CommandRunner<int>('dovetail', 'test')
      ..addCommand(NewCommand(sdkLocator: SdkLocator(home: sdkHome.path)));
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    sdkHome.deleteSync(recursive: true);
  });

  void installSdk(String version) {
    for (final String package in <String>['dovetail', 'weave_di']) {
      final Directory dir = Directory(
        p.join(sdkHome.path, 'sdk', version, 'packages', package),
      )..createSync(recursive: true);
      File(
        p.join(dir.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: $package\nversion: $version\n');
    }
  }

  // weave_di mora noutro repositorio, privado, e o portao nao pode depender de
  // um checkout dele: um teste que so passa na maquina que tem o repo ao lado
  // e exatamente o que este marco esta removendo. O fixture e um pacote de
  // verdade — pubspec com nome — porque o comando confere o pubspec.yaml antes
  // de aceitar o caminho.
  late Directory weave;
  setUp(() {
    weave = Directory.systemTemp.createTempSync('dovetail_weave');
    File(
      p.join(weave.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: weave_di\nversion: 3.3.0\n');
  });
  tearDown(() => weave.deleteSync(recursive: true));

  Future<int?> run(List<String> extra) => runner.run(<String>[
    'new',
    '--root',
    root.path,
    '--dovetail-path',
    dovetailPath,
    '--weave-path',
    weave.path,
    ...extra,
  ]);

  String read(String relative) =>
      File(p.join(root.path, relative)).readAsStringSync();

  bool exists(String relative) =>
      File(p.join(root.path, relative)).existsSync();

  group('what it scaffolds', () {
    test('should write the four files a project needs', () async {
      expect(await run(<String>['demo', '--no-create']), 0);

      expect(exists(p.join('demo', 'pubspec.yaml')), true);
      expect(exists(p.join('demo', 'dovetail.yaml')), true);
      expect(exists(p.join('demo', 'lib', 'main.dart')), true);
      expect(exists(p.join('demo', 'test', 'widget_test.dart')), true);
    });

    test('should write the clean-arch tree, the core and the bridge', () async {
      expect(await run(<String>['demo', '--no-create']), 0);

      expect(
        exists(
          p.join(
            'demo',
            'lib',
            'domain',
            'usecases',
            'home',
            'load_greeting.dart',
          ),
        ),
        true,
      );
      expect(
        exists(
          p.join('demo', 'lib', 'data', 'usecases', 'local_load_greeting.dart'),
        ),
        true,
      );
      expect(
        exists(
          p.join('demo', 'lib', 'infra', 'clock', 'system_clock_provider.dart'),
        ),
        true,
      );
      expect(
        exists(p.join('demo', 'lib', 'main', 'di', 'home_module.dart')),
        true,
      );
      expect(
        exists(
          p.join(
            'demo',
            'lib',
            'presentation',
            'presenters',
            'home',
            'change_notifier_home_presenter.dart',
          ),
        ),
        true,
      );
      expect(exists(p.join('demo', 'core', 'src', 'handle.rs')), true);
      expect(exists(p.join('demo', 'core_bridge', 'pubspec.yaml')), true);
      expect(
        exists(
          p.join('demo', 'core_bridge', 'rust', 'src', 'api', 'handle.rs'),
        ),
        true,
      );
    });

    test('the scripts should ship with the package name rendered', () async {
      expect(await run(<String>['demo', '--no-create']), 0);

      expect(
        exists(p.join('demo', 'scripts', 'checks', 'flutter', 'run_all.sh')),
        true,
      );
      expect(
        exists(p.join('demo', 'scripts', 'checks', 'rust', 'run_all.sh')),
        true,
      );
      expect(
        read(
          p.join(
            'demo',
            'scripts',
            'checks',
            'flutter',
            'check_layer_boundaries.sh',
          ),
        ),
        contains('PKG="demo"'),
        reason: 'o check de camadas tem que falar o nome do package gerado',
      );
      expect(
        read(p.join('demo', 'run_app.sh')),
        contains('scripts/checks/rust/run_all.sh'),
      );
    });

    test('the core crate should be named after the project', () async {
      expect(await run(<String>['demo', '--no-create']), 0);

      expect(
        read(p.join('demo', 'core', 'Cargo.toml')),
        contains('name = "demo_core"'),
      );
      expect(
        read(p.join('demo', 'core_bridge', 'rust', 'src', 'api', 'handle.rs')),
        contains('demo_core::CoreHandle'),
      );
      expect(
        read(p.join('demo', 'core_bridge', 'rust', 'Cargo.toml')),
        contains('demo_core = { path = "../../core" }'),
      );
    });

    test('the pubspec should wire weave_di and the bridge', () async {
      await run(<String>['demo', '--no-create']);

      final String pubspec = read(p.join('demo', 'pubspec.yaml'));
      expect(pubspec, contains('weave_di:'));
      expect(pubspec, contains('path: "${weave.path}"'));
      expect(pubspec, contains('core_bridge:'));
      expect(pubspec, contains('path: core_bridge'));
    });

    test(
      'the scaffold should refuse to version pubspec_overrides.yaml',
      () async {
        await run(<String>['demo', '--no-create']);

        // O override aponta para o SDK em caminho ABSOLUTO desta maquina.
        // Versionado, ele quebra o `flutter pub get` de todo mundo que clonar o
        // projeto — com um caminho que nao existe no disco deles. Cada um
        // regenera o seu com `dovetail upgrade`.
        expect(
          read(p.join('demo', '.gitignore')),
          contains('pubspec_overrides.yaml'),
        );
      },
    );

    test('the scripts and hooks should come out executable', () async {
      if (Platform.isWindows) {
        markTestSkipped('Windows nao tem bit de execucao');
        return;
      }
      await run(<String>['demo', '--no-create']);

      // `writeAsStringSync` cria com o modo padrao do processo, e o modo da
      // ORIGEM se perde. Os 35 `.sh` e os dois hooks saiam `rw-r--r--`: o
      // `./run_app.sh` morria com Permission denied, e — pior, porque e
      // silencioso — o git IGNORAVA os hooks. O portao que este scaffold
      // existe em boa parte para entregar nunca rodou na casa de ninguem.
      final Directory demo = Directory(p.join(root.path, 'demo'));
      final List<File> scripts = demo
          .listSync(recursive: true)
          .whereType<File>()
          .where((File each) => each.path.endsWith('.sh'))
          .toList();
      expect(scripts, isNotEmpty, reason: 'o scaffold escreve scripts');
      for (final File script in scripts) {
        expect(
          script.statSync().modeString()[2],
          'x',
          reason: '${p.relative(script.path, from: demo.path)} nao executa',
        );
      }
      for (final String hook in <String>['pre-commit', 'pre-push']) {
        expect(
          File(p.join(demo.path, '.githooks', hook)).statSync().modeString()[2],
          'x',
          reason: 'git ignora um hook sem bit, e nao diz quase nada',
        );
      }
      // E so os scripts: um `.dart` executavel seria o modo vazando.
      final Iterable<File> dartFiles = demo
          .listSync(recursive: true)
          .whereType<File>()
          .where((File each) => each.path.endsWith('.dart'));
      for (final File each in dartFiles) {
        expect(each.statSync().modeString()[2], isNot('x'));
      }
    });

    test('the pubspec should carry no git dependency at all', () async {
      await run(<String>['demo', '--no-create']);

      // weave_di era `git: url: git@weave-di.github.com:...` — um alias de SSH
      // do ~/.ssh/config de uma maquina so, herdado por TODO projeto gerado.
      // Nada aqui pode voltar a depender de git: um path que nao resolve falha
      // dizendo o caminho, um host que o DNS nao conhece falha dizendo nada.
      final String pubspec = read(p.join('demo', 'pubspec.yaml'));
      expect(pubspec, isNot(contains('git:')));
      expect(pubspec, isNot(contains('git@')));
      expect(pubspec, isNot(contains('ref:')));
    });

    test('without weave_di anywhere it should refuse, naming the ways '
        'out', () async {
      // Ambiente vazio de proposito: com `DOVETAIL_WEAVE_PATH` exportada no
      // host, um comando que lesse `Platform.environment` acharia o checkout e
      // este teste passaria a nao provar nada — foi o que aconteceu.
      final CommandRunner<int> bare = CommandRunner<int>('dovetail', 'test')
        ..addCommand(
          NewCommand(
            sdkLocator: SdkLocator(home: sdkHome.path),
            environment: const <String, String>{},
          ),
        );

      await expectLater(
        bare.run(<String>[
          'new',
          '--root',
          root.path,
          '--dovetail-path',
          dovetailPath,
          'demo',
          '--no-create',
        ]),
        throwsA(
          isA<UsageException>().having(
            (UsageException e) => '${e.message}${e.usage}',
            'names weave_di, the flag, the variable and the SDK',
            allOf(
              contains('weave_di'),
              contains('--weave-path'),
              contains(r'$DOVETAIL_WEAVE_PATH'),
              contains('self-install'),
            ),
          ),
        ),
      );
      // E recusa ANTES de escrever: um scaffold pela metade e pior do que
      // nenhum, porque o proximo `new` recusa dizendo que o diretorio existe.
      expect(Directory(p.join(root.path, 'demo')).existsSync(), isFalse);
    });

    test('the pubspec should depend on the real dovetail by path', () async {
      await run(<String>['demo', '--no-create']);

      final String pubspec = read(p.join('demo', 'pubspec.yaml'));
      expect(pubspec, contains('name: demo'));
      expect(pubspec, contains('dovetail:'));
      expect(pubspec, contains('path: "$dovetailPath"'));
    });

    test('the config should parse as the commands read it', () async {
      await run(<String>['demo', '--no-create']);

      final DovetailConfig config = DovetailConfig.parse(
        read(p.join('demo', 'dovetail.yaml')),
      );
      expect(config.identifier, 'com.example.demo');
      expect(config.targets, isNotEmpty);
    });

    test('the widget test should reference the generated app', () async {
      await run(<String>['demo', '--no-create']);

      final String test = read(p.join('demo', 'test', 'widget_test.dart'));
      expect(test, contains('package:demo/main.dart'));
      expect(test, contains('DemoApp'));
    });

    test('the widget test should exercise the dovetail runtime, not just '
        'the app', () async {
      await run(<String>['demo', '--no-create']);

      final String test = read(p.join('demo', 'test', 'widget_test.dart'));
      expect(test, contains("import 'package:dovetail/dovetail.dart';"));
      expect(
        test,
        contains('ValidationComposite'),
        reason:
            'um smoke que só renderiza o app prova o Flutter, não o SDK que o '
            'scaffold prometeu ligar',
      );
    });

    test('--identifier should override the default', () async {
      await run(<String>[
        'demo',
        '--identifier',
        'io.example.chosen',
        '--no-create',
      ]);

      final DovetailConfig config = DovetailConfig.parse(
        read(p.join('demo', 'dovetail.yaml')),
      );
      expect(config.identifier, 'io.example.chosen');
    });

    test('--name should override the directory name', () async {
      await run(<String>['demo', '--name', 'other_name', '--no-create']);

      expect(exists(p.join('other_name', 'pubspec.yaml')), true);
      expect(
        read(p.join('other_name', 'pubspec.yaml')),
        contains('name: other_name'),
      );
    });

    test('--no-create leaves the platform directories empty', () async {
      expect(await run(<String>['demo', '--no-create']), 0);

      expect(exists(p.join('demo', 'linux', 'CMakeLists.txt')), false);
      expect(exists(p.join('demo', 'pubspec.yaml')), true);
    });

    test(
      'without --no-create, flutter create fills in the platform directory',
      () async {
        if (Process.runSync('which', <String>['flutter']).exitCode != 0) {
          markTestSkipped('flutter is not installed');
          return;
        }
        expect(await run(<String>['demo']), 0);

        expect(
          exists(p.join('demo', 'linux', 'CMakeLists.txt')),
          true,
          reason:
              'flutter create should fill the linux/ directory the scaffold '
              'leaves empty',
        );
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );

    test(
      'the scaffold should be a real project: flutter test and doctor pass',
      () async {
        if (Process.runSync('which', <String>['flutter']).exitCode != 0) {
          markTestSkipped('flutter is not installed');
          return;
        }
        // Este e o unico teste que resolve o pubspec de verdade, e o template
        // importa `package:weave_di/weave_di.dart` — o fixture dos outros
        // testes tem pubspec e nao tem lib, entao aqui ele nao serve.
        //
        // Exigido por variavel, nunca sondado: uma sonda acharia o checkout
        // nesta maquina e nao no runner, e o baseline passaria a descrever
        // uma maquina em vez de um estado. Explicito, o skip e o mesmo nos
        // dois lugares — que e a propriedade que faz o baseline valer.
        final String weaveReal =
            Platform.environment['DOVETAIL_WEAVE_PATH']?.trim() ?? '';
        if (weaveReal.isEmpty ||
            !File(p.join(weaveReal, 'lib', 'weave_di.dart')).existsSync()) {
          markTestSkipped(
            r'set $DOVETAIL_WEAVE_PATH to a weave_di checkout to resolve the '
            'scaffold for real; the repository is private, so the gate cannot '
            'assume one',
          );
          return;
        }
        expect(
          await runner.run(<String>[
            'new',
            '--root',
            root.path,
            '--dovetail-path',
            dovetailPath,
            '--weave-path',
            weaveReal,
            'demo',
          ]),
          0,
        );

        final String demo = p.join(root.path, 'demo');
        final ProcessResult pubGet = Process.runSync('flutter', <String>[
          'pub',
          'get',
        ], workingDirectory: demo);
        expect(pubGet.exitCode, 0, reason: pubGet.stdout.toString());
        final ProcessResult tested = Process.runSync('flutter', <String>[
          'test',
        ], workingDirectory: demo);
        expect(tested.exitCode, 0, reason: tested.stdout.toString());

        // doctor reads the project from the cwd, so it runs through the real
        // binary pointed at the scaffold — like doctor_command_test does.
        // A fresh scaffold has no update base-url, so doctor reports the
        // project honestly and exits 2 (cannot ship yet) — that is not an
        // error; what the test holds onto is that the project was read.
        final ProcessResult doctor = Process.runSync('dart', <String>[
          'run',
          p.join(Directory.current.path, 'bin', 'dovetail.dart'),
          'doctor',
        ], workingDirectory: demo);
        expect(doctor.exitCode, isNot(1), reason: doctor.stdout.toString());
        expect(
          '${doctor.stdout}${doctor.stderr}',
          contains('identifier  com.example.demo'),
          reason: 'doctor must read the scaffold the command wrote',
        );
      },
      timeout: const Timeout(Duration(minutes: 6)),
    );
  });

  group('what it refuses', () {
    test('an invalid name should be rejected', () async {
      await expectLater(
        run(<String>['1bad']),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('not a valid project name'),
          ),
        ),
      );
    });

    test('an existing directory should not be overwritten', () async {
      Directory(p.join(root.path, 'demo')).createSync(recursive: true);

      await expectLater(
        run(<String>['demo']),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('already exists'),
          ),
        ),
      );
    });

    test('without a reachable dovetail it should refuse instead of writing a '
        'broken path', () async {
      final CommandRunner<int> bare = CommandRunner<int>('dovetail', 'test')
        ..addCommand(NewCommand(sdkLocator: SdkLocator(home: sdkHome.path)));

      await expectLater(
        bare.run(<String>['new', '--root', root.path, 'demo']),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.toString(),
            'toString()',
            contains('--dovetail-path'),
          ),
        ),
      );
      // And nothing half-written should remain.
      expect(exists(p.join('demo', 'pubspec.yaml')), false);
    });

    test('everything missing at once should be ONE refusal naming all four, '
        'not four runs', () async {
      // Ambiente vazio e SDK vazio, raiz fora do repo, templates apontados
      // para lugar nenhum: o barril, o weave_di, o template do app e o do
      // bridge faltam ao mesmo tempo. Antes, cada corrida mostrava UMA falta,
      // e a pessoa descobria a proxima so depois de consertar a anterior.
      final CommandRunner<int> bare = CommandRunner<int>('dovetail', 'test')
        ..addCommand(
          NewCommand(
            sdkLocator: SdkLocator(home: sdkHome.path),
            environment: const <String, String>{},
          ),
        );

      await expectLater(
        bare.run(<String>[
          'new',
          '--root',
          root.path,
          'demo',
          '--template',
          p.join(root.path, 'nao', 'existe'),
          '--bridge-template',
          p.join(root.path, 'nem', 'este'),
        ]),
        throwsA(
          isA<UsageException>()
              .having(
                (UsageException error) => error.message,
                'counts them',
                contains('4 things'),
              )
              .having(
                (UsageException error) => error.usage,
                'names every one of the four with its way out',
                allOf(<Matcher>[
                  contains('dovetail library'),
                  contains('--dovetail-path'),
                  contains('weave_di'),
                  contains('--weave-path'),
                  contains('app template'),
                  contains('--template'),
                  contains('bridge template'),
                  contains('--bridge-template'),
                ]),
              ),
        ),
      );
      expect(exists(p.join('demo', 'pubspec.yaml')), false);
    });
  });

  group('the installed SDK fallback', () {
    test('without --dovetail-path and without a repo, the scaffold should '
        'point at the SDK', () async {
      installSdk('0.1.0');

      final CommandRunner<int> bare = CommandRunner<int>('dovetail', 'test')
        ..addCommand(NewCommand(sdkLocator: SdkLocator(home: sdkHome.path)));

      expect(
        await bare.run(<String>[
          'new',
          '--root',
          root.path,
          'demo',
          '--no-create',
        ]),
        0,
      );

      final String pubspec = read(p.join('demo', 'pubspec.yaml'));
      expect(
        pubspec,
        contains(
          'path: "${p.normalize(p.absolute(p.join(sdkHome.path, 'sdk', '0.1.0', 'packages', 'dovetail')))}"',
        ),
      );
    });

    test('--sdk should write the placeholder pubspec and the overrides in '
        'one step', () async {
      installSdk('0.1.0');

      final CommandRunner<int> bare = CommandRunner<int>('dovetail', 'test')
        ..addCommand(NewCommand(sdkLocator: SdkLocator(home: sdkHome.path)));

      expect(
        await bare.run(<String>[
          'new',
          '--root',
          root.path,
          'demo',
          '--sdk',
          '--no-create',
        ]),
        0,
      );

      expect(
        read(p.join('demo', 'pubspec.yaml')),
        contains('path: "toolkit/dovetail"'),
        reason:
            'com --sdk o pubspec leva um placeholder e quem resolve é o '
            'override — nada de path absoluto de máquina no pubspec',
      );
      final String overrides = read(p.join('demo', 'pubspec_overrides.yaml'));
      expect(overrides, contains('dependency_overrides:'));
      expect(overrides, contains('  dovetail:'));
      expect(
        overrides,
        contains(p.join(sdkHome.path, 'sdk', '0.1.0', 'packages', 'dovetail')),
      );
    });

    test(
      '--sdk without an installed SDK refuses, naming the installer',
      () async {
        final CommandRunner<int> bare = CommandRunner<int>('dovetail', 'test')
          ..addCommand(NewCommand(sdkLocator: SdkLocator(home: sdkHome.path)));

        await expectLater(
          bare.run(<String>['new', '--root', root.path, 'demo', '--sdk']),
          throwsA(
            isA<UsageException>().having(
              (UsageException error) => error.message,
              'message',
              contains('SDK'),
            ),
          ),
        );
        expect(exists(p.join('demo', 'pubspec.yaml')), false);
      },
    );
  });
}
