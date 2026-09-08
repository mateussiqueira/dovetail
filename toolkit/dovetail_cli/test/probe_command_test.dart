import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

import 'support/stdout_capture.dart';

/// A public key and the signature the reference `minisign` tool produced over
/// the payload below, copied from `dovetail_updater`'s own test vectors. They
/// are a matching set, so the command's `run()` can be exercised all the way
/// through — including `--download`, which verifies the bytes served are the
/// bytes signed — without `minisign` on the machine.
const String _referencePublicKey = '''
untrusted comment: minisign public key 9104FC85BB0FC321
RWQhww+7hfwEkazwMrOqcOeYRd+myNTpeJJP4bRWbnbMXV3T8ZSFPajp
''';

const String _referenceSignature = '''
untrusted comment: signature from minisign secret key
RUQhww+7hfwEkWtARB009cGoM/E5aak5XOvFMIgz6fLcTBlqcBJONzflPABPaAHxnlx5ojvkzJy/zAkxwxHM+kORnis2FsJ2ygw=
trusted comment: timestamp:1788272466\tfile:small.bin\thashed
pMYx41+3aH2fe3X6jQwLD58C1SBja+rh0FHO+knc/CQedUvUQQhIR7i/l0Ra1N2Djrjm/6XRfpzmnQbF13BGBw==
''';

final Uint8List _payload = base64.decode('ZG92ZXRhaWwgdXBkYXRlIHBheWxvYWQ=');

const String _endpoint = 'https://api.example.com/latest.json';
const String _artifactUrl = 'https://cdn.example.com/app.tar.gz';

/// Answers whatever it was told to, the same way `manifest_probe_test.dart`
/// does, so the command can be driven against a manifest that never touched a
/// wire.
final class _Canned implements ArtifactFetcher {
  _Canned(this.answers);

  final Map<String, Object> answers;

  @override
  Future<FetchedBody> fetch(Uri url, {DownloadProgress? onProgress}) async {
    final Object? answer = answers[url.toString()];
    if (answer == null) {
      throw StateError('nothing canned for $url');
    }
    if (answer is int) {
      return FetchedBody(statusCode: answer, bytes: Uint8List(0));
    }
    if (answer is Uint8List) {
      return FetchedBody(statusCode: 200, bytes: answer);
    }
    return FetchedBody(
      statusCode: 200,
      bytes: Uint8List.fromList(utf8.encode(answer as String)),
    );
  }
}

/// A manifest that offers one platform, signed by [_referencePublicKey]. The
/// signature field carries base64 over the minisign text, which is the only
/// form a client in the field decodes.
String _signedManifest() => jsonEncode(<String, Object?>{
  'version': '2.0.0',
  'platforms': <String, Object?>{
    'darwin-universal': <String, Object?>{
      'url': _artifactUrl,
      'signature': base64.encode(utf8.encode(_referenceSignature)),
    },
  },
});

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('dovetail_probe_cmd'));
  tearDown(() => root.deleteSync(recursive: true));

  CommandRunner<int> runnerWith(Map<String, Object> answers) =>
      CommandRunner<int>('dovetail', 'test')
        ..addCommand(ProbeCommand(fetcher: _Canned(answers)));

  test('--url is required, and refused as usage', () async {
    // Era `mandatory: true`, que o package:args so cobra na LEITURA: o
    // ArgumentError escapava do comando, caia no catch generico do
    // bin/dovetail.dart, e quem esqueceu a flag lia "an unexpected
    // ArgumentError escaped. This is a defect in dovetail, not in your
    // project" com nove quadros de pilha de dentro do package:args — mais uma
    // entrada no log que existe para o suporte. Saia 1; todo outro erro de
    // uso desta CLI sai 64.
    await expectLater(
      runnerWith(<String, Object>{}).run(<String>['probe']),
      throwsA(
        isA<UsageException>().having(
          (UsageException failure) => failure.message,
          'message',
          contains('--url is required'),
        ),
      ),
      reason: 'the manifest endpoint is the one thing a probe cannot guess',
    );
  });

  test('without --public-key the probe should verify with the key the yaml '
      'declares, and say so', () async {
    // Um so lugar decide: a mesma chave com que o release assina e que o build
    // embute no app. A doc dizia isso antes de ser verdade.
    File(p.join(root.path, 'dovetail.yaml')).writeAsStringSync(
      'identifier: com.example.demo\nname: Demo\nmanufacturer: M\n'
      'targets: [darwin-aarch64]\n'
      'update:\n  key: keys/update.key\n'
      '  base-url: https://cdn.example.com/r\n'
      '  public-key: |\n'
      '${_referencePublicKey.trim().split('\n').map((String line) => '    $line').join('\n')}\n',
    );

    final ProcessResult ran =
        Process.runSync(Platform.resolvedExecutable, <String>[
          p.join(repoRoot(), 'toolkit', 'dovetail_cli', 'bin', 'dovetail.dart'),
          'probe',
          '--url',
          'https://cdn.example/manifest.json',
          '--timeout',
          '1',
        ], workingDirectory: root.path);

    expect(
      ran.stdout as String,
      contains('public key from dovetail.yaml'),
      reason: 'a chave veio do yaml, e o relatorio diz de onde',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('--ca that is not on disk should be refused as usage', () async {
    await expectLater(
      runnerWith(<String, Object>{}).run(<String>[
        'probe',
        '--url',
        'https://cdn.example/manifest.json',
        '--ca',
        '/nao/existe/ca.crt',
      ]),
      throwsA(
        isA<UsageException>().having(
          (UsageException failure) => failure.message,
          'message',
          contains('no CA at'),
        ),
      ),
    );
  });

  test('--timeout that is not a number of seconds should be refused', () async {
    for (final String bad in <String>['abc', '-1', '1.5']) {
      await expectLater(
        runnerWith(<String, Object>{}).run(<String>[
          'probe',
          '--url',
          'https://cdn.example/manifest.json',
          '--timeout',
          bad,
        ]),
        throwsA(
          isA<UsageException>().having(
            (UsageException failure) => failure.message,
            'message',
            allOf(contains('--timeout'), contains(bad)),
          ),
        ),
        reason: bad,
      );
    }
  });

  test(
    '--timeout 0 should be accepted as "wait as long as the OS does"',
    () async {
      // Com o fetcher injetado a rede nao entra; o que se prova e que zero
      // passa pela validacao em vez de ser recusado como "nao positivo".
      final int? code =
          await runnerWith(<String, Object>{
            'https://cdn.example/manifest.json': _signedManifest(),
          }).run(<String>[
            'probe',
            '--url',
            'https://cdn.example/manifest.json',
            '--target',
            'darwin-universal',
            '--timeout',
            '0',
          ]);

      expect(code, isNotNull);
    },
  );

  test('a --url that is not a url should be refused, naming it', () async {
    await expectLater(
      runnerWith(
        <String, Object>{},
      ).run(<String>['probe', '--url', 'http://[']),
      throwsA(
        isA<UsageException>().having(
          (UsageException error) => error.message,
          'message',
          contains('--url is not a url'),
        ),
      ),
    );
  });

  test('a --public-key that is not on disk should be refused', () async {
    final String missing = p.join(root.path, 'no-such-key.pub');
    await expectLater(
      runnerWith(
        <String, Object>{},
      ).run(<String>['probe', '--url', _endpoint, '--public-key', missing]),
      throwsA(
        isA<UsageException>().having(
          (UsageException error) => error.message,
          'message',
          contains('no public key at'),
        ),
      ),
    );
  });

  test('--download without --public-key should refuse, and say why', () async {
    await expectLater(
      runnerWith(
        <String, Object>{},
      ).run(<String>['probe', '--url', _endpoint, '--download']),
      throwsA(
        isA<UsageException>().having(
          (UsageException error) => error.usage,
          'usage',
          contains('came from the same place'),
        ),
      ),
      reason:
          'verifying an artefact against the key that signed it proves only '
          'that the two came from the same place',
    );
  });

  test('a manifest that serves what the client reads should pass', () async {
    final CapturedStdout out = CapturedStdout();
    final int? code = await capturingStdout(
      out,
      () => runnerWith(<String, Object>{_endpoint: _signedManifest()}).run(
        <String>['probe', '--url', _endpoint, '--target', 'darwin-universal'],
      ),
    );
    expect(code, 0);
    expect(out.text.toString(), contains('probe: ok'));
  });

  test(
    '--public-key should be read and checked against the signature',
    () async {
      final String key = p.join(root.path, 'update.pub');
      File(key).writeAsStringSync(_referencePublicKey);

      final CapturedStdout out = CapturedStdout();
      final int? code = await capturingStdout(
        out,
        () => runnerWith(<String, Object>{_endpoint: _signedManifest()}).run(
          <String>[
            'probe',
            '--url',
            _endpoint,
            '--target',
            'darwin-universal',
            '--public-key',
            key,
          ],
        ),
      );
      expect(code, 0);
      expect(
        out.text.toString(),
        contains('against key id 9104FC85BB0FC321'),
        reason: 'the run has to name the key it checked against',
      );
    },
  );

  test('a --public-key that does not parse should fail the run', () async {
    final String key = p.join(root.path, 'garbage.pub');
    File(key).writeAsStringSync('not a minisign key');

    final CapturedStdout out = CapturedStdout();
    final int? code = await capturingStdout(
      out,
      () => runnerWith(<String, Object>{_endpoint: _signedManifest()}).run(
        <String>[
          'probe',
          '--url',
          _endpoint,
          '--target',
          'darwin-universal',
          '--public-key',
          key,
        ],
      ),
    );
    expect(code, 1);
    expect(
      out.text.toString(),
      contains('does not parse'),
      reason: 'a bad key has to fail the run, not be silently skipped',
    );
  });

  test(
    '--download should verify the bytes served are the bytes signed',
    () async {
      final String key = p.join(root.path, 'update.pub');
      File(key).writeAsStringSync(_referencePublicKey);

      final CapturedStdout out = CapturedStdout();
      final int? code = await capturingStdout(
        out,
        () =>
            runnerWith(<String, Object>{
              _endpoint: _signedManifest(),
              _artifactUrl: _payload,
            }).run(<String>[
              'probe',
              '--url',
              _endpoint,
              '--target',
              'darwin-universal',
              '--public-key',
              key,
              '--download',
            ]),
      );
      expect(code, 0, reason: out.text.toString());
      expect(out.text.toString(), contains('the artefact verifies'));
    },
  );
}
