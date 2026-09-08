import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dovetail_signer/dovetail_signer.dart' as signer;
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

bool get _haveMinisign =>
    Process.runSync('which', <String>['minisign']).exitCode == 0;

void main() {
  late Directory root;
  late String secretKey;
  late String publicKey;
  late CommandRunner<int> runner;

  const String password = 'release-key-password';

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_relcmd');
    secretKey = p.join(root.path, 'sec.key');
    publicKey = p.join(root.path, 'pub.key');
    runner = CommandRunner<int>('dovetail', 'test')
      ..addCommand(ReleaseCommand());
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<void> generateKey({bool unencrypted = false}) async {
    final signer.ProcessOutcome outcome =
        await const signer.SystemProcessRunner().run('minisign', <String>[
          '-G',
          '-f',
          if (unencrypted) '-W',
          '-p',
          publicKey,
          '-s',
          secretKey,
        ], stdin: unencrypted ? null : '$password\n$password\n');
    expect(outcome.succeeded, true, reason: outcome.stderr);
  }

  String artifactAt(String name) {
    final String path = p.join(root.path, name);
    File(path).writeAsStringSync('the bytes of $name');
    return path;
  }

  String out() => p.join(root.path, 'dist', 'latest.json');

  List<String> argumentsFor(
    Map<String, String> artifacts, {
    bool unencrypted = false,
  }) => <String>[
    'release',
    '--version',
    '2.1.0',
    '--notes',
    'the release notes',
    '--key',
    secretKey,
    '--out',
    out(),
    // Declarar a chave publica e obrigatorio: sem ela nada confere que o
    // release e assinado pela chave que os clientes instalados confiam, e foi
    // por essa porta que saiu um release que o app recusa.
    '--public-key',
    publicKey,
    if (unencrypted) '--unencrypted-key',
    for (final MapEntry<String, String> entry in artifacts.entries) ...<String>[
      '--artifact',
      '${entry.key}=https://cdn.example.com/${p.basename(entry.value)}='
          '${entry.value}',
    ],
  ];

  Map<String, Object?> writtenManifest() =>
      jsonDecode(File(out()).readAsStringSync()) as Map<String, Object?>;

  test('should sign every artefact and write one manifest', () async {
    if (!_haveMinisign) {
      markTestSkipped('minisign is not installed');
      return;
    }
    await generateKey(unencrypted: true);

    final int code =
        await runner.run(
          argumentsFor(<String, String>{
            'darwin-universal': artifactAt('client_universal.app.tar.gz'),
            'windows-x86_64': artifactAt('client_x64_setup.exe'),
            'linux-aarch64': artifactAt('client_arm64.deb'),
          }, unencrypted: true),
        ) ??
        1;

    expect(code, 0);
    final Map<String, Object?> platforms =
        writtenManifest()['platforms']! as Map<String, Object?>;
    expect(platforms.keys, hasLength(3));
    for (final String name in <String>[
      'client_universal.app.tar.gz.minisig',
      'client_x64_setup.exe.minisig',
      'client_arm64.deb.minisig',
    ]) {
      expect(File(p.join(root.path, name)).existsSync(), true, reason: name);
    }
  });

  test('what it writes should verify against the public key', () async {
    if (!_haveMinisign) {
      markTestSkipped('minisign is not installed');
      return;
    }
    await generateKey(unencrypted: true);

    final String artifact = artifactAt('client_universal.app.tar.gz');
    await runner.run(
      argumentsFor(<String, String>{
        'darwin-universal': artifact,
      }, unencrypted: true),
    );

    final UpdateManifest manifest = ManifestParser.parse(
      File(out()).readAsStringSync(),
    );
    expect(
      () => MinisignVerifier.verify(
        payload: File(artifact).readAsBytesSync(),
        signature: MinisignSignature.parse(
          manifest.releaseFor('darwin-universal').signature,
        ),
        publicKey: MinisignPublicKey.parse(File(publicKey).readAsStringSync()),
      ),
      returnsNormally,
      reason:
          'this is the whole point: the command output is what a client reads',
    );
  });

  test(
    'a client in the field should be able to decode what it wrote',
    () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      await generateKey(unencrypted: true);

      final String artifact = artifactAt('client_universal.app.tar.gz');
      await runner.run(
        argumentsFor(<String, String>{
          'darwin-universal': artifact,
        }, unencrypted: true),
      );

      final Map<String, Object?> platforms =
          writtenManifest()['platforms']! as Map<String, Object?>;
      final String field =
          (platforms['darwin-universal']! as Map<String, Object?>)['signature']!
              as String;

      // Deliberately not MinisignSignature.parse: that unwraps either form, so
      // it is exactly the leniency that let the command write the raw text for
      // as long as it did. A client already in the field does base64 first and
      // has no fallback, so the test has to do the same.
      final String decoded = utf8.decode(base64.decode(field));

      expect(
        decoded,
        startsWith('untrusted comment:'),
        reason:
            'the manifest carries base64 on top of the minisign text; the raw '
            'text decodes to nothing a client can parse, and it finds out on a '
            'machine nobody here can see',
      );
      expect(
        decoded,
        File('$artifact.minisig').readAsStringSync(),
        reason: 'the field is the .minisig on disk, byte for byte',
      );
    },
  );

  test('the trusted comment should name the version and the file', () async {
    if (!_haveMinisign) {
      markTestSkipped('minisign is not installed');
      return;
    }
    await generateKey(unencrypted: true);

    final String artifact = artifactAt('client_arm64.deb');
    await runner.run(
      argumentsFor(<String, String>{
        'linux-aarch64': artifact,
      }, unencrypted: true),
    );

    final String comment = MinisignSignature.parse(
      ManifestParser.parse(
        File(out()).readAsStringSync(),
      ).releaseFor('linux-aarch64').signature,
    ).trustedComment;

    expect(comment, contains('version:2.1.0'));
    expect(comment, contains('file:client_arm64.deb'));
  });

  test('should read the password from the environment', () async {
    if (!_haveMinisign) {
      markTestSkipped('minisign is not installed');
      return;
    }
    await generateKey();

    final ProcessResult ran = Process.runSync(
      Platform.resolvedExecutable,
      <String>[
        'run',
        p.join(Directory.current.path, 'bin', 'dovetail.dart'),
        ...argumentsFor(<String, String>{
          'darwin-universal': artifactAt('client.app.tar.gz'),
        }),
      ],
      environment: <String, String>{'DOVETAIL_UPDATE_KEY_PASSWORD': password},
    );

    expect(ran.exitCode, 0, reason: ran.stderr.toString());
    expect(File(out()).existsSync(), true);
  });

  test('an unset password variable should refuse, not assume empty', () async {
    if (!_haveMinisign) {
      markTestSkipped('minisign is not installed');
      return;
    }
    await generateKey();

    await expectLater(
      runner.run(<String>[
        ...argumentsFor(<String, String>{
          'darwin-universal': artifactAt('client.app.tar.gz'),
        }),
        '--password-env',
        'A_VARIABLE_NOBODY_EXPORTED',
      ]),
      throwsA(
        isA<UsageException>().having(
          (UsageException error) => error.message,
          'message',
          contains('A_VARIABLE_NOBODY_EXPORTED'),
        ),
      ),
    );
    expect(File(out()).existsSync(), false);
  });

  test('the same platform twice should be refused', () async {
    final String first = artifactAt('a.tar.gz');
    final String second = artifactAt('b.tar.gz');
    await expectLater(
      runner.run(<String>[
        'release',
        '--version',
        '2.1.0',
        '--key',
        secretKey,
        '--out',
        out(),
        '--unencrypted-key',
        '--artifact',
        'darwin-universal=https://cdn/a=$first',
        '--artifact',
        'darwin-universal=https://cdn/b=$second',
      ]),
      throwsA(
        isA<UsageException>().having(
          (UsageException error) => error.usage,
          'usage',
          contains('silently replace'),
        ),
      ),
    );
  });

  test('an artefact that is not on disk should be refused', () async {
    await expectLater(
      runner.run(
        argumentsFor(<String, String>{
          'darwin-universal': p.join(root.path, 'never-built.tar.gz'),
        }, unencrypted: true),
      ),
      throwsA(isA<UsageException>()),
    );
  });

  test('a malformed artefact triple should be refused', () async {
    await expectLater(
      runner.run(<String>[
        'release',
        '--version',
        '2.1.0',
        '--key',
        secretKey,
        '--unencrypted-key',
        '--artifact',
        'darwin-universal=https://cdn/a',
      ]),
      throwsA(isA<UsageException>()),
    );
  });

  test('--public-key should win over update.public-key, so a staging release '
      'never edits the production yaml', () async {
    if (!_haveMinisign) {
      markTestSkipped('minisign is not installed');
      return;
    }
    await generateKey(unencrypted: true);
    // O yaml declara OUTRA chave (a de dev do repositorio); a flag traz a que
    // assina. Com o yaml vencendo, o release recusava a propria assinatura
    // como estranha — e o unico jeito de um staging passar era editar o yaml
    // de producao.
    File(p.join(root.path, 'dovetail.yaml')).writeAsStringSync(
      'identifier: com.example.demo\nname: Demo\nmanufacturer: M\n'
      'targets: [darwin-aarch64, windows-x86_64, linux-aarch64]\n'
      'update:\n  key: sec.key\n  unencrypted: true\n'
      '  base-url: https://cdn.example.com/r\n'
      '  public-key: |\n'
      '    untrusted comment: minisign public key D18395BE8A6B994E\n'
      '    RWROmWuKvpWD0RErEh4kcn0sjuu4dQYX5MERE9dNGuImxQXHzNuRYLVP\n',
    );

    final int code =
        await runner.run(<String>[
          ...argumentsFor(<String, String>{
            'darwin-universal': artifactAt('client_universal.app.tar.gz'),
          }, unencrypted: true),
          '--root',
          root.path,
        ]) ??
        1;

    expect(code, 0);
    expect(File(out()).existsSync(), true);
  });

  test('--public-key and --out given relative should resolve against --root, '
      'like --artifact does', () async {
    if (!_haveMinisign) {
      markTestSkipped('minisign is not installed');
      return;
    }
    await generateKey(unencrypted: true);
    File(p.join(root.path, 'dovetail.yaml')).writeAsStringSync(
      'identifier: com.example.demo\nname: Demo\nmanufacturer: M\n'
      'targets: [darwin-aarch64]\n'
      'update:\n  key: sec.key\n  unencrypted: true\n'
      '  base-url: https://cdn.example.com/r\n',
    );
    artifactAt('client_universal.app.tar.gz');

    // Nada aqui e absoluto exceto --root: a chave publica pelo nome ao lado da
    // secreta, o manifesto em dist/, o artefato pelo nome. Antes, o
    // `--public-key pub.key` nao existia no cwd do teste, o TEXTO "pub.key"
    // virava a chave e o parse morria; o `--out` ia para o dist/ do cwd.
    final int code =
        await runner.run(<String>[
          'release',
          '--root',
          root.path,
          '--version',
          '2.1.0',
          '--key',
          secretKey,
          '--unencrypted-key',
          '--public-key',
          'pub.key',
          '--out',
          'dist/latest.json',
          '--artifact',
          'darwin-universal=client_universal.app.tar.gz',
        ]) ??
        1;

    expect(code, 0);
    expect(
      File(p.join(root.path, 'dist', 'latest.json')).existsSync(),
      true,
      reason: 'o manifesto foi para o dist/ do projeto, nao para o do cwd',
    );
  });

  test('a release with no declared public key should be refused', () async {
    // A guarda que compara as duas chaves existia e nunca disparava: ela saia
    // cedo quando nada era declarado, e o yaml do produto nao declarava. Um
    // release assinado com a chave de dev passou por aqui e o app, compilado
    // para confiar noutra, o recusa. Nao declarar deixou de ser uma opcao.
    final List<String> withoutKey = argumentsFor(<String, String>{
      'darwin-aarch64': artifactAt('app.dmg'),
    }, unencrypted: true);
    withoutKey.remove('--public-key');
    withoutKey.remove(publicKey);

    await expectLater(
      runner.run(withoutKey),
      throwsA(
        isA<ConfigFailure>()
            .having(
              (ConfigFailure failure) => failure.message,
              'message',
              contains('no public key is declared'),
            )
            .having(
              (ConfigFailure failure) => failure.remedy,
              'remedy',
              allOf(contains('update.public-key'), contains('--public-key')),
            ),
      ),
    );
    // E recusa ANTES de assinar: nada de `.minisig` orfao no disco.
    expect(File(p.join(root.path, 'app.dmg.minisig')).existsSync(), isFalse);
  });

  test('no artefact at all should be refused', () async {
    await expectLater(
      runner.run(<String>[
        'release',
        '--version',
        '2.1.0',
        '--key',
        secretKey,
        '--unencrypted-key',
      ]),
      throwsA(isA<UsageException>()),
    );
  });

  test(
    'a password-protected key called unencrypted should fail',
    () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      await generateKey();

      await expectLater(
        runner.run(
          argumentsFor(<String, String>{
            'darwin-universal': artifactAt('client.app.tar.gz'),
          }, unencrypted: true),
        ),
        throwsA(isA<signer.SigningFailure>()),
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
