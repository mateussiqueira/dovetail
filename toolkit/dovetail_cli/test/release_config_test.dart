import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

bool get _hasMinisign =>
    Process.runSync('which', <String>['minisign']).exitCode == 0;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_release');
    Directory(p.join(root.path, 'dist')).createSync();
    Directory(p.join(root.path, 'keys')).createSync();
    File(
      p.join(root.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: demo_app\nversion: 3.4.0+12\n');
    File(p.join(root.path, 'dist', 'Demo.dmg')).writeAsStringSync('mac bytes');
    File(p.join(root.path, 'dist', 'demo.deb')).writeAsStringSync('deb bytes');
  });

  tearDown(() => root.deleteSync(recursive: true));

  // `publicKey` deixou de ser opcional na pratica: declarar a chave que os
  // clientes confiam e obrigatorio, entao o helper a fornece por padrao e
  // `noPublicKey: true` e como um teste pede o caso sem ela — explicito, em
  // vez de ser o default silencioso que deixou um release sair com a chave
  // errada.
  void configure({
    String? baseUrl,
    String? publicKey,
    bool noPublicKey = false,
    String targets = 'darwin-aarch64, linux-x86_64',
  }) {
    if (publicKey == null && !noPublicKey) {
      // A chave EM SI, nao o caminho: `keys/` e gitignored, entao um caminho
      // apontaria para um arquivo que nao existe num clone. Do arquivo de duas
      // linhas do minisign so a segunda — a primeira e o comentario, e um
      // scalar YAML nao aceita quebra.
      final File pub = File(p.join(root.path, 'keys', 'update.pub'));
      if (pub.existsSync()) {
        // O base64 do arquivo inteiro — a forma de UMA linha. A chave sozinha
        // nao serve: `MinisignPublicKey.parse` exige o comentario junto, e um
        // scalar YAML nao aceita quebra sem bloco.
        publicKey = base64.encode(utf8.encode(pub.readAsStringSync()));
      }
    }
    File(p.join(root.path, ConfigLocator.fileName)).writeAsStringSync('''
identifier: com.example.demo
name: Demo
manufacturer: Example Ltda
targets: [$targets]
update:
  key: keys/update.key
  password-env: DEMO_KEY_PASSWORD
${baseUrl == null ? '' : '  base-url: $baseUrl\n'}${publicKey == null ? '' : '  public-key: $publicKey\n'}  manifest: dist/latest.json
''');
  }

  bool generateKey() {
    if (!_hasMinisign) {
      return false;
    }
    Process.runSync('minisign', <String>[
      '-G',
      '-W',
      '-p',
      p.join(root.path, 'keys', 'update.pub'),
      '-s',
      p.join(root.path, 'keys', 'update.key'),
    ]);
    return File(p.join(root.path, 'keys', 'update.key')).existsSync();
  }

  String tauriShaped(String publicKeyFile) => base64.encode(
    utf8.encode(
      File(p.join(root.path, 'keys', publicKeyFile)).readAsStringSync(),
    ),
  );

  bool generateStrangerKey() {
    if (!_hasMinisign) {
      return false;
    }
    Process.runSync('minisign', <String>[
      '-G',
      '-W',
      '-p',
      p.join(root.path, 'keys', 'stranger.pub'),
      '-s',
      p.join(root.path, 'keys', 'stranger.key'),
    ]);
    return File(p.join(root.path, 'keys', 'stranger.pub')).existsSync();
  }

  // --root, never Directory.current: cwd belongs to the PROCESS, and every
  // suite in a `dart test` run is an isolate of that one process.
  Future<int?> release(List<String> extra) =>
      (CommandRunner<int>(
        'dovetail',
        'test',
      )..addCommand(ReleaseCommand())).run(<String>[
        'release',
        '--root',
        root.path,
        '--unencrypted-key',
        ...extra,
      ]);

  Map<String, Object?> manifest() =>
      jsonDecode(
            File(p.join(root.path, 'dist', 'latest.json')).readAsStringSync(),
          )
          as Map<String, Object?>;

  group('what the config supplies so the command line does not', () {
    test('the version should come from pubspec, without the build '
        'number', () async {
      if (!generateKey()) {
        markTestSkipped('minisign is needed to sign anything');
        return;
      }
      configure(baseUrl: 'https://cdn.example.com/releases');

      expect(
        await release(<String>['--artifact', 'darwin-aarch64=dist/Demo.dmg']),
        0,
      );
      expect(manifest()['version'], '3.4.0');
    });

    test('the url should be built from base-url, version and file', () async {
      if (!generateKey()) {
        markTestSkipped('minisign is needed to sign anything');
        return;
      }
      configure(baseUrl: 'https://cdn.example.com/releases');

      await release(<String>['--artifact', 'darwin-aarch64=dist/Demo.dmg']);

      final Map<String, Object?> platforms =
          manifest()['platforms']! as Map<String, Object?>;
      expect(
        (platforms['darwin-aarch64']! as Map<String, Object?>)['url'],
        'https://cdn.example.com/releases/3.4.0/Demo.dmg',
      );
    });

    test('the manifest should land where the config says', () async {
      if (!generateKey()) {
        markTestSkipped('minisign is needed to sign anything');
        return;
      }
      configure(baseUrl: 'https://cdn.example.com/releases');

      await release(<String>['--artifact', 'linux-x86_64=dist/demo.deb']);

      expect(File(p.join(root.path, 'dist', 'latest.json')).existsSync(), true);
    });
  });

  group('what it refuses before anything is signed', () {
    test('a platform key outside the protocol vocabulary', () async {
      configure();

      await expectLater(
        release(<String>[
          '--artifact',
          'darwin-arm64=https://cdn/x=dist/Demo.dmg',
        ]),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('arm64'),
          ),
        ),
        reason:
            'a key the client never asks for publishes a release nobody sees, '
            'and nothing later in the pipeline would have noticed',
      );
    });

    test('a platform key the product does not declare', () async {
      configure(targets: 'darwin-aarch64');

      await expectLater(
        release(<String>[
          '--artifact',
          'linux-x86_64=https://cdn/x=dist/demo.deb',
        ]),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('not one of the targets'),
          ),
        ),
      );
    });

    test('a universal key should be accepted for a declared os', () async {
      if (!generateKey()) {
        markTestSkipped('minisign is needed to sign anything');
        return;
      }
      configure(
        baseUrl: 'https://cdn.example.com/r',
        targets: 'darwin-aarch64, darwin-x86_64',
      );

      expect(
        await release(<String>['--artifact', 'darwin-universal=dist/Demo.dmg']),
        0,
        reason:
            'targets names the two architectures a client asks for, and one '
            'fat artefact answers both under the universal key that '
            'releaseFor falls back to',
      );
    });

    test(
      'a universal key for an os with no target should still refuse',
      () async {
        configure(targets: 'linux-x86_64');

        await expectLater(
          release(<String>[
            '--artifact',
            'darwin-universal=https://cdn/x=dist/Demo.dmg',
          ]),
          throwsA(
            isA<UsageException>().having(
              (UsageException error) => error.message,
              'message',
              contains('not one of the targets'),
            ),
          ),
        );
      },
    );

    test('the short form with no base-url configured', () async {
      configure();

      await expectLater(
        release(<String>['--artifact', 'darwin-aarch64=dist/Demo.dmg']),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('no url'),
          ),
        ),
      );
    });
  });

  group('the long form, which has to keep working', () {
    test('a url carrying a query string should survive intact', () async {
      if (!generateKey()) {
        markTestSkipped('minisign is needed to sign anything');
        return;
      }
      configure();

      await release(<String>[
        '--artifact',
        'darwin-aarch64=https://cdn/app.dmg?v=3&t=x=dist/Demo.dmg',
      ]);

      final Map<String, Object?> platforms =
          manifest()['platforms']! as Map<String, Object?>;
      expect(
        (platforms['darwin-aarch64']! as Map<String, Object?>)['url'],
        'https://cdn/app.dmg?v=3&t=x',
        reason:
            'splitting on every = truncated the url at its first parameter, '
            'and the manifest pointed at an artefact that would 404',
      );
    });

    test('an explicit --version should win over pubspec', () async {
      if (!generateKey()) {
        markTestSkipped('minisign is needed to sign anything');
        return;
      }
      configure(baseUrl: 'https://cdn.example.com/r');

      await release(<String>[
        '--version',
        '9.9.9',
        '--artifact',
        'darwin-aarch64=dist/Demo.dmg',
      ]);

      expect(manifest()['version'], '9.9.9');
    });
  });

  group('the key the park trusts', () {
    test('a key the declared public key does not match should be '
        'refused', () async {
      if (!generateKey() || !generateStrangerKey()) {
        markTestSkipped('minisign is needed to sign anything');
        return;
      }
      // Signed by keys/update.key, but the project declares the stranger's
      // public half as the one every client carries.
      configure(
        baseUrl: 'https://cdn.example.com/releases',
        publicKey: tauriShaped('stranger.pub'),
      );

      await expectLater(
        release(<String>['--artifact', 'darwin-aarch64=dist/Demo.dmg']),
        throwsA(
          isA<ConfigFailure>().having(
            (ConfigFailure failure) => failure.message,
            'message',
            allOf(contains('signs as'), contains('update.public-key is')),
          ),
        ),
        reason:
            'Tauri compares the two ids, warns and finishes the build, so the '
            'release only fails on a stranger machine that cannot install it',
      );
      expect(
        File(p.join(root.path, 'dist', 'latest.json')).existsSync(),
        false,
        reason: 'a manifest no client accepts should never reach the disk',
      );
    });

    test('the matching key should sign and write as before', () async {
      if (!generateKey()) {
        markTestSkipped('minisign is needed to sign anything');
        return;
      }
      configure(
        baseUrl: 'https://cdn.example.com/releases',
        publicKey: tauriShaped('update.pub'),
      );

      expect(
        await release(<String>['--artifact', 'darwin-aarch64=dist/Demo.dmg']),
        0,
      );
      expect(manifest()['version'], '3.4.0');
    });

    test('no declared public key should be refused', () async {
      if (!generateKey()) {
        markTestSkipped('minisign is needed to sign anything');
        return;
      }
      configure(baseUrl: 'https://cdn.example.com/releases', noPublicKey: true);

      // Este teste afirmava o contrario — que nao declarar "fica fora do
      // caminho" —, e o raciocinio era que um projeto sem parque nao esta
      // assinando com a chave errada. O que ele nao previu e que a checagem
      // mais importante do comando ficava desligada por omissao: o yaml do
      // produto nao declarava, e saiu um release assinado com a chave de dev
      // que o app, compilado para confiar noutra, recusa. Um release que
      // ninguem consegue instalar nao e um release.
      await expectLater(
        release(<String>['--artifact', 'darwin-aarch64=dist/Demo.dmg']),
        throwsA(
          isA<ConfigFailure>().having(
            (ConfigFailure failure) => failure.message,
            'message',
            contains('no public key is declared'),
          ),
        ),
      );
    });
  });
}
