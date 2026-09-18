import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _publicKey = '''
untrusted comment: minisign public key 9104FC85BB0FC321
RWQhww+7hfwEkazwMrOqcOeYRd+myNTpeJJP4bRWbnbMXV3T8ZSFPajp
''';

const String _signature = '''
untrusted comment: signature from minisign secret key
RUQhww+7hfwEkWtARB009cGoM/E5aak5XOvFMIgz6fLcTBlqcBJONzflPABPaAHxnlx5ojvkzJy/zAkxwxHM+kORnis2FsJ2ygw=
trusted comment: timestamp:1788272466\tfile:small.bin\thashed
pMYx41+3aH2fe3X6jQwLD58C1SBja+rh0FHO+knc/CQedUvUQQhIR7i/l0Ra1N2Djrjm/6XRfpzmnQbF13BGBw==
''';

const String _payloadBase64 = 'ZG92ZXRhaWwgdXBkYXRlIHBheWxvYWQ=';

final class ScriptedFetcher implements ArtifactFetcher {
  ScriptedFetcher(this.responses);

  final Map<String, FetchedBody> responses;
  final List<Uri> requested = <Uri>[];

  @override
  Future<FetchedBody> fetch(Uri url, {DownloadProgress? onProgress}) async {
    requested.add(url);
    final FetchedBody? body = responses[url.toString()];
    if (body == null) {
      throw const SocketException('nothing listening');
    }
    onProgress?.call(body.bytes.length, body.bytes.length);
    return body;
  }
}

final class MidStreamFetcher implements ArtifactFetcher {
  MidStreamFetcher({required this.manifestUrl, required this.manifest});

  final String manifestUrl;
  final String manifest;
  final List<Uri> requested = <Uri>[];

  @override
  Future<FetchedBody> fetch(Uri url, {DownloadProgress? onProgress}) async {
    requested.add(url);
    if (url.toString() == manifestUrl) {
      return jsonBody(manifest);
    }
    onProgress?.call(11, 38);
    throw const UpdateFailure('the download stopped after 11 of 38 bytes.');
  }
}

FetchedBody jsonBody(String body) =>
    FetchedBody(statusCode: 200, bytes: Uint8List.fromList(utf8.encode(body)));

String manifestFor(String version, String url, String signature) =>
    jsonEncode(<String, Object?>{
      'version': version,
      'platforms': <String, Object?>{
        'darwin-aarch64': <String, Object?>{'url': url, 'signature': signature},
      },
    });

void main() {
  const String primary = 'https://a.example.com/manifest.json';
  const String secondary = 'https://b.example.com/manifest.json';
  const String artefactUrl = 'https://cdn.example.com/app.tar.gz';

  UpdateFlow flowWith(ScriptedFetcher fetcher) => UpdateFlow(
    fetcher: fetcher,
    publicKey: _publicKey,
    platformKey: 'darwin-aarch64',
  );

  group('check', () {
    test('should refuse to run with no endpoint configured', () async {
      await expectLater(
        flowWith(
          ScriptedFetcher(const <String, FetchedBody>{}),
        ).check(endpoints: const <String>[], installed: Version.parse('1.0.0')),
        throwsA(isA<UpdateFailure>()),
      );
    });

    test('should offer a newer version from the first endpoint', () async {
      final ScriptedFetcher fetcher = ScriptedFetcher(<String, FetchedBody>{
        primary: jsonBody(manifestFor('2.0.0', artefactUrl, 'sig')),
      });

      final UpdateCheck check = await flowWith(fetcher).check(
        endpoints: const <String>[primary, secondary],
        installed: Version.parse('1.0.0'),
      );

      expect(check.shouldUpdate, true);
      expect(check.endpoint, primary);
      expect(fetcher.requested.length, 1);
    });

    test(
      'should fall through to the next endpoint when the first is down',
      () async {
        final ScriptedFetcher fetcher = ScriptedFetcher(<String, FetchedBody>{
          secondary: jsonBody(manifestFor('2.0.0', artefactUrl, 'sig')),
        });

        final UpdateCheck check = await flowWith(fetcher).check(
          endpoints: const <String>[primary, secondary],
          installed: Version.parse('1.0.0'),
        );

        expect(check.endpoint, secondary);
        expect(fetcher.requested.map((Uri u) => u.toString()), <String>[
          primary,
          secondary,
        ]);
      },
    );

    test('should read 204 as no update and stop asking', () async {
      final ScriptedFetcher fetcher = ScriptedFetcher(<String, FetchedBody>{
        primary: FetchedBody(statusCode: 204, bytes: Uint8List(0)),
      });

      final UpdateCheck check = await flowWith(fetcher).check(
        endpoints: const <String>[primary, secondary],
        installed: Version.parse('1.0.0'),
      );

      expect(check.shouldUpdate, false);
      expect(fetcher.requested.length, 1);
    });

    test('should try the next endpoint on a non success status', () async {
      final ScriptedFetcher fetcher = ScriptedFetcher(<String, FetchedBody>{
        primary: FetchedBody(statusCode: 500, bytes: Uint8List(0)),
        secondary: jsonBody(manifestFor('2.0.0', artefactUrl, 'sig')),
      });

      final UpdateCheck check = await flowWith(fetcher).check(
        endpoints: const <String>[primary, secondary],
        installed: Version.parse('1.0.0'),
      );

      expect(check.endpoint, secondary);
    });

    test(
      'should fail with the last reason when every endpoint fails',
      () async {
        final ScriptedFetcher fetcher = ScriptedFetcher(
          const <String, FetchedBody>{},
        );

        await expectLater(
          flowWith(fetcher).check(
            endpoints: const <String>[primary, secondary],
            installed: Version.parse('1.0.0'),
          ),
          throwsA(
            isA<UpdateFailure>().having(
              (UpdateFailure failure) => failure.message,
              'message',
              contains('every update endpoint failed'),
            ),
          ),
        );
        expect(fetcher.requested.length, 2);
      },
    );
  });

  group('download', () {
    test('should return a verified artefact for a good signature', () async {
      final ScriptedFetcher fetcher = ScriptedFetcher(<String, FetchedBody>{
        primary: jsonBody(manifestFor('2.0.0', artefactUrl, _signature)),
        artefactUrl: FetchedBody(
          statusCode: 200,
          bytes: base64.decode(_payloadBase64),
        ),
      });
      final UpdateFlow sut = flowWith(fetcher);
      final UpdateCheck check = await sut.check(
        endpoints: const <String>[primary],
        installed: Version.parse('1.0.0'),
      );

      final VerifiedArtifact artefact = await sut.download(check.manifest!);

      expect(artefact.length, base64.decode(_payloadBase64).length);
      expect(artefact.sourceUrl, artefactUrl);
      expect(artefact.trustedComment, contains('file:small.bin'));
    });

    test('should report progress while it downloads', () async {
      final ScriptedFetcher fetcher = ScriptedFetcher(<String, FetchedBody>{
        primary: jsonBody(manifestFor('2.0.0', artefactUrl, _signature)),
        artefactUrl: FetchedBody(
          statusCode: 200,
          bytes: base64.decode(_payloadBase64),
        ),
      });
      final UpdateFlow sut = flowWith(fetcher);
      final UpdateCheck check = await sut.check(
        endpoints: const <String>[primary],
        installed: Version.parse('1.0.0'),
      );
      final List<int> seen = <int>[];

      await sut.download(
        check.manifest!,
        onProgress: (int received, int? total) => seen.add(received),
      );

      expect(seen, isNotEmpty);
    });

    test('should refuse an artefact whose bytes were altered', () async {
      final Uint8List tampered = Uint8List.fromList(
        base64.decode(_payloadBase64),
      )..[0] ^= 0x01;
      final ScriptedFetcher fetcher = ScriptedFetcher(<String, FetchedBody>{
        primary: jsonBody(manifestFor('2.0.0', artefactUrl, _signature)),
        artefactUrl: FetchedBody(statusCode: 200, bytes: tampered),
      });
      final UpdateFlow sut = flowWith(fetcher);
      final UpdateCheck check = await sut.check(
        endpoints: const <String>[primary],
        installed: Version.parse('1.0.0'),
      );

      await expectLater(
        sut.download(check.manifest!),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.message,
            'message',
            contains('does not match its signature'),
          ),
        ),
      );
    });

    test('should refuse an artefact the server would not serve', () async {
      final ScriptedFetcher fetcher = ScriptedFetcher(<String, FetchedBody>{
        primary: jsonBody(manifestFor('2.0.0', artefactUrl, _signature)),
        artefactUrl: FetchedBody(statusCode: 404, bytes: Uint8List(0)),
      });
      final UpdateFlow sut = flowWith(fetcher);
      final UpdateCheck check = await sut.check(
        endpoints: const <String>[primary],
        installed: Version.parse('1.0.0'),
      );

      await expectLater(
        sut.download(check.manifest!),
        throwsA(isA<UpdateFailure>()),
      );
    });
  });

  group('a manifest that lies', () {
    const String pub = '''
untrusted comment: minisign public key E5ECCFCD331EB7E1
RWThtx4zzc/s5YWbax/f/yvmHhsTCpUrIFG1UfS87M1/qY7xI46bl1IX
''';
    const String signatureAlpha = '''
untrusted comment: signature from minisign secret key
RUThtx4zzc/s5VdggSvo9vfwKeIVDZh/JZAR6ZxCwcN5Jp+bOrOpfApHoBYIYn/nZepZJDqttm8Utb+1N+ANXdggpMtqK0JfnwI=
trusted comment: fixture
DRsQ0abzxa+z9vfB+I/AuPea9Er7Rh95quNLEnDvA0mQTH4uKc7D/iqHq1/oK/2Xm9EQvNHV6PX6uqCYDrKlBA==
''';
    const String signatureBeta = '''
untrusted comment: signature from minisign secret key
RUThtx4zzc/s5SiA7qTTRtqg/BNR9oNB4g3SAbsVSbK+pw6X0ACMlbXaiwB0o9n9n87Gcm2ZtKcgc0cFFp+eaoNxz8x9GDcCrQQ=
trusted comment: fixture
dqjWEu8VN7vb4dsXYncNMdPhjgdf/clj9uM7lB5+zarDb0ak6/mzv2BckKEuOJTFtSHg+uBy3bi5GptrGO4+DA==
''';
    const String payloadAlphaBase64 = 'cGF5bG9hZC1BTFBIQS0wMTIzNDU2Nzg5';

    UpdateFlow flowWith(ScriptedFetcher fetcher) => UpdateFlow(
      fetcher: fetcher,
      publicKey: pub,
      platformKey: 'darwin-aarch64',
    );

    test('should accept an artefact its signature does cover', () async {
      final ScriptedFetcher fetcher = ScriptedFetcher(<String, FetchedBody>{
        primary: jsonBody(manifestFor('2.0.0', artefactUrl, signatureAlpha)),
        artefactUrl: FetchedBody(
          statusCode: 200,
          bytes: base64.decode(payloadAlphaBase64),
        ),
      });
      final UpdateFlow sut = flowWith(fetcher);
      final UpdateCheck check = await sut.check(
        endpoints: const <String>[primary],
        installed: Version.parse('1.0.0'),
      );

      final VerifiedArtifact artefact = await sut.download(check.manifest!);

      expect(artefact.length, base64.decode(payloadAlphaBase64).length);
    });

    test('should refuse a manifest whose signature was issued for another '
        'artefact', () async {
      final ScriptedFetcher fetcher = ScriptedFetcher(<String, FetchedBody>{
        primary: jsonBody(manifestFor('2.0.0', artefactUrl, signatureBeta)),
        artefactUrl: FetchedBody(
          statusCode: 200,
          bytes: base64.decode(payloadAlphaBase64),
        ),
      });
      final UpdateFlow sut = flowWith(fetcher);
      final UpdateCheck check = await sut.check(
        endpoints: const <String>[primary],
        installed: Version.parse('1.0.0'),
      );

      await expectLater(
        sut.download(check.manifest!),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.message,
            'message',
            contains('does not match its signature'),
          ),
        ),
      );
    });
  });

  group('a download that dies and a version that was never published', () {
    test('should refuse a download that dies mid stream', () async {
      final MidStreamFetcher fetcher = MidStreamFetcher(
        manifestUrl: primary,
        manifest: manifestFor('2.0.0', artefactUrl, _signature),
      );
      final UpdateFlow sut = UpdateFlow(
        fetcher: fetcher,
        publicKey: _publicKey,
        platformKey: 'darwin-aarch64',
      );
      final UpdateCheck check = await sut.check(
        endpoints: const <String>[primary],
        installed: Version.parse('1.0.0'),
      );

      await expectLater(
        sut.download(check.manifest!),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.message,
            'message',
            contains('11 of 38 bytes'),
          ),
        ),
      );
      expect(fetcher.requested.last.toString(), artefactUrl);
    });

    test('should refuse a manifest that announces a version the host never '
        'published', () async {
      final ScriptedFetcher fetcher = ScriptedFetcher(<String, FetchedBody>{
        primary: jsonBody(manifestFor('2.0.0', artefactUrl, _signature)),
        artefactUrl: FetchedBody(statusCode: 404, bytes: Uint8List(0)),
      });
      final UpdateFlow sut = flowWith(fetcher);
      final UpdateCheck check = await sut.check(
        endpoints: const <String>[primary],
        installed: Version.parse('1.0.0'),
      );

      await expectLater(
        sut.download(check.manifest!),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.message,
            'message',
            contains('404'),
          ),
        ),
      );
    });

    test(
      'should refuse a manifest that carries no release for this platform',
      () async {
        final ScriptedFetcher fetcher = ScriptedFetcher(<String, FetchedBody>{
          primary: jsonBody(
            jsonEncode(<String, Object?>{
              'version': '2.0.0',
              'platforms': <String, Object?>{
                'windows-x86_64': <String, Object?>{
                  'url': artefactUrl,
                  'signature': _signature,
                },
              },
            }),
          ),
        });
        final UpdateFlow sut = flowWith(fetcher);
        final UpdateCheck check = await sut.check(
          endpoints: const <String>[primary],
          installed: Version.parse('1.0.0'),
        );

        await expectLater(
          sut.download(check.manifest!),
          throwsA(isA<UpdateFailure>()),
        );
      },
    );
  });

  group('install on macOS', () {
    late Directory root;
    late Directory installed;

    setUp(() {
      root = Directory.systemTemp.createTempSync('dovetail_install');
      installed = Directory(p.join(root.path, 'Example.app'))..createSync();
      File(p.join(installed.path, 'version.txt')).writeAsStringSync('1.0.0');
    });

    tearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });

    Uint8List archiveWithNewBundle(String version) {
      final Directory staging = Directory(p.join(root.path, 'staging'))
        ..createSync();
      final Directory bundle = Directory(p.join(staging.path, 'Example.app'))
        ..createSync();
      File(p.join(bundle.path, 'version.txt')).writeAsStringSync(version);

      final ProcessResult tarred = Process.runSync('tar', <String>[
        '-czf',
        p.join(root.path, 'update.tar.gz'),
        '-C',
        staging.path,
        'Example.app',
      ]);
      expect(tarred.exitCode, 0, reason: tarred.stderr.toString());
      staging.deleteSync(recursive: true);

      return File(p.join(root.path, 'update.tar.gz')).readAsBytesSync();
    }

    test(
      'should replace the installed bundle with the one in the archive',
      () async {
        if (!Platform.isMacOS) {
          markTestSkipped('needs macOS for tar and the bundle layout');
          return;
        }

        final MacosInstaller sut = MacosInstaller(
          runner: const SystemProcessRunner(),
          bundlePath: installed.path,
        );

        final InstallOutcome outcome = await sut.install(
          VerifiedArtifact.trusted(
            bytes: archiveWithNewBundle('2.0.0'),
            sourceUrl: artefactUrl,
            trustedComment: 'timestamp:1\tfile:update.tar.gz',
          ),
        );

        expect(outcome, InstallOutcome.installedRestartNeeded);
        expect(
          File(p.join(installed.path, 'version.txt')).readAsStringSync(),
          '2.0.0',
        );
      },
    );

    test('should leave nothing behind after a successful swap', () async {
      if (!Platform.isMacOS) {
        markTestSkipped('needs macOS');
        return;
      }

      final MacosInstaller sut = MacosInstaller(
        runner: const SystemProcessRunner(),
        bundlePath: installed.path,
      );

      await sut.install(
        VerifiedArtifact.trusted(
          bytes: archiveWithNewBundle('2.0.0'),
          sourceUrl: artefactUrl,
          trustedComment: 'c',
        ),
      );

      expect(Directory('${installed.path}.previous').existsSync(), false);
    });

    test(
      'should refuse an archive with no bundle and keep the old one',
      () async {
        if (!Platform.isMacOS) {
          markTestSkipped('needs macOS');
          return;
        }

        final Directory staging = Directory(p.join(root.path, 'plain'))
          ..createSync();
        File(p.join(staging.path, 'readme.txt')).writeAsStringSync('nothing');
        Process.runSync('tar', <String>[
          '-czf',
          p.join(root.path, 'bad.tar.gz'),
          '-C',
          staging.path,
          'readme.txt',
        ]);

        final MacosInstaller sut = MacosInstaller(
          runner: const SystemProcessRunner(),
          bundlePath: installed.path,
        );

        await expectLater(
          sut.install(
            VerifiedArtifact.trusted(
              bytes: File(p.join(root.path, 'bad.tar.gz')).readAsBytesSync(),
              sourceUrl: artefactUrl,
              trustedComment: 'c',
            ),
          ),
          throwsA(
            isA<UpdateFailure>().having(
              (UpdateFailure failure) => failure.remedy,
              'remedy',
              contains('Nothing was replaced'),
            ),
          ),
        );

        expect(
          File(p.join(installed.path, 'version.txt')).readAsStringSync(),
          '1.0.0',
        );
      },
    );

    test('should refuse to install over a path that has no bundle', () async {
      final MacosInstaller sut = MacosInstaller(
        runner: const SystemProcessRunner(),
        bundlePath: p.join(root.path, 'Absent.app'),
      );

      await expectLater(
        sut.install(
          VerifiedArtifact.trusted(
            bytes: Uint8List(0),
            sourceUrl: artefactUrl,
            trustedComment: 'c',
          ),
        ),
        throwsA(isA<UpdateFailure>()),
      );
    });
  });
}
