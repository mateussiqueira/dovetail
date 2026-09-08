import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:dovetail_signer/dovetail_signer.dart' as signer;
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

bool get _haveMinisign =>
    Process.runSync('which', <String>['minisign']).exitCode == 0;

/// Answers whatever it was told to, so the probe can be exercised against
/// every shape a server can be in without one running.
final class _Canned implements ArtifactFetcher {
  _Canned(this.answers);

  final Map<String, Object> answers;
  final List<Uri> asked = <Uri>[];

  @override
  Future<FetchedBody> fetch(Uri url, {DownloadProgress? onProgress}) async {
    asked.add(url);
    final Object? answer = answers[url.toString()];
    if (answer == null) {
      throw StateError('nothing canned for $url');
    }
    if (answer is Object Function()) {
      answer();
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

const String _endpoint = 'https://api.example.com/latest.json';
const String _artifactUrl = 'https://cdn.example.com/app.tar.gz';

ProbeFinding _finding(ProbeReport report, String what, {String? target}) =>
    report.findings.firstWhere(
      (ProbeFinding finding) =>
          finding.what == what && finding.target == target,
      orElse: () => throw StateError(
        'no finding "$what"${target == null ? '' : ' for $target'} in\n'
        '${report.findings.join('\n')}',
      ),
    );

void main() {
  late Directory root;
  String? secretKey;
  String? publicKeyText;
  String? signatureText;
  late Uint8List payload;

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('dovetail_probe');
    payload = Uint8List.fromList(utf8.encode('the bytes a client downloads'));
    if (!_haveMinisign) {
      return;
    }
    // Once for the whole file: a minisign key costs seconds because scrypt
    // is meant to, and nothing here is about generating one.
    secretKey = p.join(root.path, 'sec.key');
    final String publicKey = p.join(root.path, 'pub.key');
    await const signer.SystemProcessRunner().run('minisign', <String>[
      '-G',
      '-f',
      '-W',
      '-p',
      publicKey,
      '-s',
      secretKey!,
    ]);
    publicKeyText = File(publicKey).readAsStringSync();

    final String artifact = p.join(root.path, 'app.tar.gz');
    File(artifact).writeAsBytesSync(payload);
    await const signer.UpdateSigner(runner: signer.SystemProcessRunner()).sign(
      artifactPath: artifact,
      secretKeyPath: secretKey!,
      access: const signer.UnencryptedKey(),
      trustedComment: 'version:2.0.0\tfile:app.tar.gz',
    );
    signatureText = File('$artifact.minisig').readAsStringSync();
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  String manifestWith(
    String signature, {
    String version = '2.0.0',
    List<String> platforms = const <String>['darwin-universal'],
  }) => jsonEncode(<String, Object?>{
    'version': version,
    'platforms': <String, Object?>{
      for (final String key in platforms)
        key: <String, Object?>{'url': _artifactUrl, 'signature': signature},
    },
  });

  Future<ProbeReport> probe(
    Map<String, Object> answers, {
    List<String> targets = const <String>['darwin-universal'],
    String? publicKey,
    Version? installed,
    bool download = false,
    String url = _endpoint,
  }) => ManifestProbe(fetcher: _Canned(answers)).run(
    url: Uri.parse(url),
    targets: targets,
    publicKey: publicKey,
    installed: installed,
    download: download,
  );

  group('before it even asks', () {
    test('a plain http endpoint should be refused, and say why', () async {
      final ProbeReport report = await probe(
        <String, Object>{},
        url: 'http://api.example.com/latest.json',
      );
      expect(report.passed, false);
      expect(
        report.findings.single.detail,
        contains('rests entirely on the transport'),
        reason:
            'the manifest carries no signature of its own, so http is not a '
            'smaller problem than a bad signature — it is the same one',
      );
    });
  });

  group('what the server answers', () {
    test('a 500 should be reported as a broken endpoint', () async {
      final ProbeReport report = await probe(<String, Object>{_endpoint: 500});
      expect(report.passed, false);
      expect(_finding(report, 'the endpoint answers').detail, contains('500'));
    });

    test('a 204 should not be mistaken for a manifest', () async {
      final ProbeReport report = await probe(<String, Object>{_endpoint: 204});
      expect(report.passed, false);
      expect(
        _finding(report, 'the endpoint answers').detail,
        contains('nothing new'),
      );
    });

    test('a body that is not a manifest should stop the run there', () async {
      final ProbeReport report = await probe(<String, Object>{
        _endpoint: '{"update_available": true, "latest_version": "2.0.0"}',
      });
      expect(report.passed, false);
      expect(_finding(report, 'the body parses as a manifest').passed, false);
      expect(
        report.findings.where((ProbeFinding finding) => finding.target != null),
        isEmpty,
        reason: 'nothing per-platform can be said about a body that is not one',
      );
    });
  });

  group('the signature field', () {
    test('the raw minisign text should be refused, not accepted', () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      final ProbeReport report = await probe(<String, Object>{
        _endpoint: manifestWith(signatureText!),
      });
      expect(report.passed, false);
      expect(
        _finding(
          report,
          'the signature field decodes',
          target: 'darwin-universal',
        ).detail,
        contains('never the text itself'),
        reason:
            'this is the bug the probe exists to catch on somebody else machine: '
            'a client decodes base64 before it parses, and the raw form '
            'decodes to nothing',
      );
    });

    test('base64 over the text should be read, and named', () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      final ProbeReport report = await probe(<String, Object>{
        _endpoint: manifestWith(base64.encode(utf8.encode(signatureText!))),
      });
      expect(report.passed, true, reason: report.findings.join('\n'));
      expect(
        _finding(
          report,
          'the signature field decodes',
          target: 'darwin-universal',
        ).detail,
        contains('version:2.0.0'),
      );
    });

    test('base64 of something else should be caught after decoding', () async {
      final ProbeReport report = await probe(<String, Object>{
        _endpoint: manifestWith(base64.encode(utf8.encode('not a signature'))),
      });
      expect(report.passed, false);
      expect(
        _finding(
          report,
          'the signature field decodes',
          target: 'darwin-universal',
        ).detail,
        contains('what came out is not minisign'),
      );
    });
  });

  group('the key', () {
    test('without one, the run should say what it did not check', () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      final ProbeReport report = await probe(<String, Object>{
        _endpoint: manifestWith(base64.encode(utf8.encode(signatureText!))),
      });
      expect(
        _finding(report, 'the signing key is checked').detail,
        contains('would pass this run'),
        reason:
            'a green run that checked nothing is worse than a red one, so it '
            'has to say so on its own',
      );
    });

    test('a signature by another key should be refused by key id', () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      final String otherPublic = p.join(root.path, 'other.pub');
      await const signer.SystemProcessRunner().run('minisign', <String>[
        '-G',
        '-f',
        '-W',
        '-p',
        otherPublic,
        '-s',
        p.join(root.path, 'other.key'),
      ]);

      final ProbeReport report = await probe(<String, Object>{
        _endpoint: manifestWith(base64.encode(utf8.encode(signatureText!))),
      }, publicKey: File(otherPublic).readAsStringSync());
      expect(report.passed, false);
      expect(
        _finding(
          report,
          'the signature is by the key this client trusts',
          target: 'darwin-universal',
        ).detail,
        contains('Every install would refuse this release'),
      );
    });
  });

  group('the three targets', () {
    test('a manifest that serves one of three should name the two', () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      final ProbeReport report = await probe(
        <String, Object>{
          _endpoint: manifestWith(
            base64.encode(utf8.encode(signatureText!)),
            platforms: <String>['windows-x86_64'],
          ),
        },
        targets: <String>['darwin-universal', 'windows-x86_64', 'linux-x86_64'],
      );
      expect(report.passed, false);
      expect(report.failures, 2);
      expect(
        _finding(
          report,
          'the manifest offers this platform',
          target: 'windows-x86_64',
        ).passed,
        true,
        reason: 'this is the shape production is in today, measured',
      );
    });

    test('darwin-universal should answer for an arch-specific ask', () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      final ProbeReport report = await probe(
        <String, Object>{
          _endpoint: manifestWith(base64.encode(utf8.encode(signatureText!))),
        },
        targets: <String>['darwin-aarch64'],
      );
      expect(report.passed, true, reason: report.findings.join('\n'));
    });
  });

  group('the policy', () {
    test(
      'a client already on the newest should be told it would not',
      () async {
        if (!_haveMinisign) {
          markTestSkipped('minisign is not installed');
          return;
        }
        final ProbeReport report = await probe(<String, Object>{
          _endpoint: manifestWith(base64.encode(utf8.encode(signatureText!))),
        }, installed: Version.parse('2.0.0'));
        expect(report.passed, false);
        expect(
          _finding(
            report,
            'the policy would offer this to 2.0.0',
            target: 'darwin-universal',
          ).passed,
          false,
        );
      },
    );

    test('an older client should be offered the update', () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      final ProbeReport report = await probe(<String, Object>{
        _endpoint: manifestWith(base64.encode(utf8.encode(signatureText!))),
      }, installed: Version.parse('1.0.0'));
      expect(report.passed, true, reason: report.findings.join('\n'));
    });
  });

  group('downloading the artefact', () {
    test('the bytes served should be the bytes signed', () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      final ProbeReport report = await probe(
        <String, Object>{
          _endpoint: manifestWith(base64.encode(utf8.encode(signatureText!))),
          _artifactUrl: payload,
        },
        publicKey: publicKeyText,
        download: true,
      );
      expect(report.passed, true, reason: report.findings.join('\n'));
      expect(
        _finding(
          report,
          'the artefact verifies',
          target: 'darwin-universal',
        ).detail,
        contains('the bytes served are the bytes signed'),
      );
    });

    test(
      'one changed byte should be caught here, not on a user machine',
      () async {
        if (!_haveMinisign) {
          markTestSkipped('minisign is not installed');
          return;
        }
        final Uint8List tampered = Uint8List.fromList(payload)
          ..[0] = payload[0] ^ 0x01;

        final ProbeReport report = await probe(
          <String, Object>{
            _endpoint: manifestWith(base64.encode(utf8.encode(signatureText!))),
            _artifactUrl: tampered,
          },
          publicKey: publicKeyText,
          download: true,
        );
        expect(report.passed, false);
        expect(
          _finding(
            report,
            'the artefact verifies',
            target: 'darwin-universal',
          ).detail,
          contains('Every install would refuse it'),
        );
      },
    );
  });

  group('what the product backend answers', () {
    // A forma exata que DesktopVersionService.manifestFor devolve, no
    // vpn.tv-back-end. Copiada, e não gerada, porque os dois lados são repos
    // separados e não há junta mais barata — do outro lado o contrapeso é
    // src/desktop-version/manifest.spec.ts, que prende a mesma forma contra o
    // serviço. Se um dos dois mudar sozinho, um dos dois cai.
    const String fromNest =
        '{'
        '"version":"2.1.0",'
        '"notes":"Corrige a reconexão silenciosa.",'
        '"pub_date":"2026-09-03T00:00:00.000Z",'
        '"platforms":{"darwin-universal":{'
        '"url":"https://updates.example.com/desktop-version/download/a3f1",'
        '"signature":"SIGNATURE"}}}';

    test('a client asking for its own arch should find the release', () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      final ProbeReport report = await probe(
        <String, Object>{
          _endpoint: fromNest.replaceFirst(
            'SIGNATURE',
            base64.encode(utf8.encode(signatureText!)),
          ),
        },
        targets: <String>['darwin-aarch64'],
        installed: Version.parse('2.0.0'),
      );

      expect(report.passed, true, reason: report.findings.join('\n'));
    });

    test(
      'the notes and the date it carries should be read, not tripped over',
      () async {
        if (!_haveMinisign) {
          markTestSkipped('minisign is not installed');
          return;
        }
        final UpdateManifest manifest = ManifestParser.parse(
          fromNest.replaceFirst(
            'SIGNATURE',
            base64.encode(utf8.encode(signatureText!)),
          ),
        );

        expect(manifest.notes, contains('reconexão'));
        expect(manifest.publishedAt, DateTime.utc(2026, 9, 3));
        expect(manifest.releaseFor('darwin-aarch64').url, endsWith('/a3f1'));
      },
    );
  });

  group('the command', () {
    CommandRunner<int> runnerWith(Map<String, Object> answers) =>
        CommandRunner<int>('dovetail', 'test')
          ..addCommand(ProbeCommand(fetcher: _Canned(answers)));

    test('a target that is not a platform key should be refused here', () {
      expect(
        () => runnerWith(
          <String, Object>{},
        ).run(<String>['probe', '--url', _endpoint, '--target', 'macos-arm64']),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('macos-arm64'),
          ),
        ),
        reason:
            'a typo in a platform key would otherwise come back as "the '
            'manifest does not offer this", which blames the server for a '
            'mistake made on the command line',
      );
    });

    test('--download without a key should refuse, and explain', () {
      expect(
        () => runnerWith(
          <String, Object>{},
        ).run(<String>['probe', '--url', _endpoint, '--download']),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.usage,
            'usage',
            contains('came from the same place'),
          ),
        ),
      );
    });

    test('an --installed that is not a version should be refused', () {
      expect(
        () => runnerWith(
          <String, Object>{},
        ).run(<String>['probe', '--url', _endpoint, '--installed', 'latest']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
