import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_build');
  });

  tearDown(() => root.deleteSync(recursive: true));

  // --root, never Directory.current: cwd belongs to the PROCESS, and
  // `dart test` runs every suite as an isolate of one process. A suite that
  // parks it in a temp directory makes any other suite that derives a path
  // from it skip, or fail, in silence — and the skip looks legitimate.
  Future<int?> build(List<String> extra) =>
      (CommandRunner<int>('dovetail', 'test')..addCommand(BuildCommand())).run(
        <String>['build', '--root', root.path, ...extra],
      );

  void configure(String targets) {
    File(p.join(root.path, ConfigLocator.fileName)).writeAsStringSync(
      'identifier: com.example.demo\nname: Demo\nmanufacturer: Example Ltda\ntargets: [$targets]\n',
    );
  }

  group('the arguments it hands flutter', () {
    test('release should be the default and debug should be explicit', () {
      expect(FlutterBuild.argumentsFor('macos'), <String>[
        'build',
        'macos',
        '--release',
      ]);
      expect(FlutterBuild.argumentsFor('linux', release: false), <String>[
        'build',
        'linux',
        '--debug',
      ]);
    });

    test('extra arguments should be passed through, after the mode', () {
      expect(
        FlutterBuild.argumentsFor(
          'windows',
          extra: <String>['--dart-define=FOO=1'],
        ),
        <String>['build', 'windows', '--release', '--dart-define=FOO=1'],
      );
    });

    test('defines should come after the mode and before extra arguments', () {
      expect(
        FlutterBuild.argumentsFor(
          'macos',
          defines: <String, String>{'dovetail.version': '1.2.3'},
          extra: <String>['--verbose'],
        ),
        <String>[
          'build',
          'macos',
          '--release',
          '--dart-define=dovetail.version=1.2.3',
          '--verbose',
        ],
      );
    });

    test('the defines should carry what the yaml decides, key as one line', () {
      final DovetailConfig config = DovetailConfig.parse(
        'identifier: com.example.demo\nname: Demo\nmanufacturer: M\n'
        'targets: [darwin-aarch64]\n'
        'update:\n  key: keys/update.key\n'
        '  base-url: https://cdn.example.com/r\n'
        '  endpoint: https://api.example.com/check/{{target}}\n'
        '  public-key: |\n'
        '    untrusted comment: minisign public key D18395BE8A6B994E\n'
        '    RWROmWuKvpWD0RErEh4kcn0sjuu4dQYX5MERE9dNGuImxQXHzNuRYLVP\n',
      );

      final Map<String, String> defines = BuildDefines.of(
        config: config,
        appVersion: '1.2.3',
      );

      expect(defines['dovetail.identifier'], 'com.example.demo');
      expect(defines['dovetail.version'], '1.2.3');
      expect(defines['dovetail.update.base_url'], 'https://cdn.example.com/r');
      expect(
        defines['dovetail.update.endpoint'],
        'https://api.example.com/check/{{target}}',
      );
      expect(
        defines['dovetail.update.public_key'],
        isNot(contains('\n')),
        reason: 'um --dart-define e uma linha; a chave vai em base64',
      );
      expect(
        MinisignPublicKey.parse(
          defines['dovetail.update.public_key']!,
        ).keyIdHex,
        'D18395BE8A6B994E',
        reason: 'o que o app vai ler e a mesma chave que o yaml declara',
      );
      expect(
        BuildDefines.describe(defines).join('\n'),
        contains('<key D18395BE8A6B994E>'),
        reason: 'o build diz o que embutiu, sem despejar base64',
      );
    });

    test('a yaml with no update section should embed only the identity', () {
      final Map<String, String> defines = BuildDefines.of(
        config: DovetailConfig.parse(
          'identifier: com.example.demo\nname: Demo\nmanufacturer: M\n'
          'targets: [darwin-aarch64]\n',
        ),
      );

      expect(defines, <String, String>{
        'dovetail.identifier': 'com.example.demo',
      });
    });

    test('every target should name where its output lands', () {
      for (final String target in <String>['macos', 'windows', 'linux']) {
        expect(FlutterBuild.outputFor[target], isNotNull, reason: target);
      }
    });
  });

  group('the ceiling it refuses at', () {
    test('a build for the host should be allowed', () {
      expect(
        () => FlutterBuild.refuseCrossCompile('macos', 'macos'),
        returnsNormally,
      );
    });

    test('a build for another host should be refused before flutter runs', () {
      expect(
        () => FlutterBuild.refuseCrossCompile('windows', 'macos'),
        throwsA(
          isA<ConfigFailure>()
              .having(
                (ConfigFailure failure) => failure.message,
                'message',
                contains('needs a windows machine'),
              )
              .having(
                (ConfigFailure failure) => failure.remedy,
                'remedy',
                contains('runner per operating system'),
              ),
        ),
        reason:
            'Flutter refuses it too, and refusing here says which step needs '
            'another machine rather than letting the build fail deep inside',
      );
    });

    test('the remedy should spell the host the way flutter does', () {
      try {
        FlutterBuild.refuseCrossCompile('macos', 'linux');
        fail('it should have refused');
      } on ConfigFailure catch (failure) {
        expect(failure.remedy, contains('macOS hosts'));
      }
    });

    test('asking for a target this host cannot build should refuse', () async {
      final String other = Platform.isMacOS ? 'linux' : 'macos';

      await expectLater(
        build(<String>['--target', other]),
        throwsA(isA<ConfigFailure>()),
      );
    });
  });

  group('which targets it picks with no --target', () {
    test('a config that declares this host should build it', () async {
      configure(Platform.isMacOS ? 'darwin-aarch64' : 'linux-x86_64');

      final int? code = await build(<String>['--flutter', 'true']);

      expect(code, 0);
    });

    test(
      'a config that declares no target for this host should do nothing',
      () async {
        configure(Platform.isMacOS ? 'windows-x86_64' : 'darwin-aarch64');

        expect(
          await build(<String>['--flutter', 'false']),
          0,
          reason:
              'a host with nothing to build is not an error; it is a runner '
              'whose part of the matrix is somewhere else',
        );
      },
    );

    test('the yaml public key should reach flutter as a --dart-define', () async {
      configure(Platform.isMacOS ? 'darwin-aarch64' : 'linux-x86_64');
      File(p.join(root.path, ConfigLocator.fileName)).writeAsStringSync(
        'identifier: com.example.demo\nname: Demo\nmanufacturer: Example Ltda\n'
        'targets: [${Platform.isMacOS ? 'darwin-aarch64' : 'linux-x86_64'}]\n'
        'update:\n  key: keys/update.key\n'
        '  base-url: https://cdn.example.com/r\n'
        '  public-key: |\n'
        '    untrusted comment: minisign public key D18395BE8A6B994E\n'
        '    RWROmWuKvpWD0RErEh4kcn0sjuu4dQYX5MERE9dNGuImxQXHzNuRYLVP\n',
      );
      File(
        p.join(root.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: demo\nversion: 1.2.3+4\n');
      final File recorder = File(p.join(root.path, 'flutter'))
        ..writeAsStringSync(
          '#!/bin/sh\nprintf "%s\\n" "\$@" > "\$(dirname "\$0")/args.txt"\n',
        );
      Process.runSync('chmod', <String>['+x', recorder.path]);

      expect(await build(<String>['--flutter', recorder.path]), 0);

      final String args = File(
        p.join(root.path, 'args.txt'),
      ).readAsStringSync();
      expect(args, contains('--dart-define=dovetail.version=1.2.3'));
      expect(args, contains('--dart-define=dovetail.update.public_key='));
      expect(
        args,
        contains(
          '--dart-define=dovetail.update.base_url=https://cdn.example.com/r',
        ),
      );
    });

    test('a failing flutter should surface its exit code', () async {
      configure(Platform.isMacOS ? 'darwin-aarch64' : 'linux-x86_64');

      expect(await build(<String>['--flutter', 'false']), isNot(0));
    });
  });
}
