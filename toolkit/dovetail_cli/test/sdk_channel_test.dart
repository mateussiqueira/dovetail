import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:dovetail_cli/src/dovetail_version.dart';
import 'package:dovetail_cli/src/sdk/sdk_channel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

final class _CannedFetcher implements ArtifactFetcher {
  _CannedFetcher(this.responses);

  final Map<String, FetchedBody> responses;

  @override
  Future<FetchedBody> fetch(Uri url, {DownloadProgress? onProgress}) async =>
      responses[url.path] ?? FetchedBody(statusCode: 404, bytes: Uint8List(0));
}

void main() {
  SdkChannel channel(Map<String, FetchedBody> responses) => SdkChannel(
    baseUrl: 'https://releases.example.com/',
    fetcher: _CannedFetcher(responses),
  );

  group('latest', () {
    test(
      'should come back trimmed of the newline the channel writes',
      () async {
        final SdkChannel c = channel(<String, FetchedBody>{
          '/latest': FetchedBody(
            statusCode: 200,
            bytes: Uint8List.fromList(utf8.encode('  0.2.0\n')),
          ),
        });

        expect(await c.latest(), '0.2.0');
      },
    );

    test('a 204 means no release yet, not an error', () async {
      final SdkChannel c = channel(<String, FetchedBody>{
        '/latest': FetchedBody(statusCode: 204, bytes: Uint8List(0)),
      });

      expect(await c.latest(), isNull);
    });

    test('an empty body means no release yet, not an error', () async {
      final SdkChannel c = channel(<String, FetchedBody>{
        '/latest': FetchedBody(statusCode: 200, bytes: Uint8List(0)),
      });

      expect(await c.latest(), isNull);
    });

    test('a broken channel is refused, naming the endpoint', () async {
      final SdkChannel c = channel(<String, FetchedBody>{
        '/latest': FetchedBody(statusCode: 500, bytes: Uint8List(0)),
      });

      await expectLater(
        c.latest(),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure error) => error.message,
            'message',
            contains('/latest'),
          ),
        ),
      );
    });
  });

  group('download', () {
    final List<int> payload = utf8.encode('the tarball');
    final String expected = sha256.convert(payload).toString();

    Map<String, FetchedBody> happyPath() => <String, FetchedBody>{
      '/0.1.0/${SdkChannel.tarballName('0.1.0')}': FetchedBody(
        statusCode: 200,
        bytes: Uint8List.fromList(payload),
      ),
      '/0.1.0/${SdkChannel.tarballName('0.1.0')}.sha256': FetchedBody(
        statusCode: 200,
        bytes: Uint8List.fromList(utf8.encode('$expected\n')),
      ),
    };

    test('should write the bytes after the sha256 matches', () async {
      final Directory dir = Directory.systemTemp.createTempSync('dt_dl');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File target = File('${dir.path}/sdk.tar.gz');

      await channel(happyPath()).download('0.1.0', target);

      expect(target.readAsBytesSync(), payload);
    });

    test('a tarball that fails the sha256 never touches the disk', () async {
      final Directory dir = Directory.systemTemp.createTempSync('dt_dl');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File target = File('${dir.path}/sdk.tar.gz');
      final Map<String, FetchedBody> poisoned = happyPath();
      poisoned['/0.1.0/${SdkChannel.tarballName('0.1.0')}.sha256'] =
          FetchedBody(
            statusCode: 200,
            bytes: Uint8List.fromList(utf8.encode('${'0' * 64}\n')),
          );

      await expectLater(
        channel(poisoned).download('0.1.0', target),
        throwsA(isA<UpdateFailure>()),
      );
      expect(target.existsSync(), false);
    });

    test('a channel without the .sha256 is refused — it is part of the '
        'release', () async {
      final Directory dir = Directory.systemTemp.createTempSync('dt_dl');
      addTearDown(() => dir.deleteSync(recursive: true));
      final File target = File('${dir.path}/sdk.tar.gz');
      final Map<String, FetchedBody> missingSum = happyPath()
        ..remove('/0.1.0/${SdkChannel.tarballName('0.1.0')}.sha256');

      await expectLater(
        channel(missingSum).download('0.1.0', target),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure error) => error.message,
            'message',
            contains('.sha256'),
          ),
        ),
      );
      expect(target.existsSync(), false);
    });

    test('a missing tarball is refused, naming the version', () async {
      final Directory dir = Directory.systemTemp.createTempSync('dt_dl');
      addTearDown(() => dir.deleteSync(recursive: true));

      await expectLater(
        channel(
          <String, FetchedBody>{},
        ).download('0.1.0', File('${dir.path}/x')),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure error) => error.message,
            'message',
            contains('0.1.0'),
          ),
        ),
      );
    });
  });

  group('naming', () {
    test('the tarball name carries version, os and arch of the binary', () {
      expect(
        SdkChannel.tarballName('0.1.0'),
        'dovetail-sdk-0.1.0-${DovetailVersion.targetOs}-'
        '${DovetailVersion.targetArch}.tar.gz',
      );
    });

    test('the urls hang off the base without doubling the slash', () {
      final SdkChannel c = channel(<String, FetchedBody>{});

      expect(
        c.tarballUrl('0.1.0').toString(),
        'https://releases.example.com/0.1.0/${SdkChannel.tarballName('0.1.0')}',
      );
      expect(
        c.shaUrl('0.1.0').toString(),
        'https://releases.example.com/0.1.0/${SdkChannel.tarballName('0.1.0')}.sha256',
      );
    });
  });

  group('baseUrlOf', () {
    test('the flag wins over the environment', () {
      expect(
        SdkChannel.baseUrlOf('https://flag.example'),
        'https://flag.example',
      );
    });

    test('without a flag and without the env, it refuses naming both', () {
      expect(
        () => SdkChannel.baseUrlOf(null),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.toString(),
            'toString()',
            contains(SdkChannel.installUrlEnv),
          ),
        ),
      );
    });
  });

  group('signature', () {
    late Directory dir;
    late MinisignPublicKey key;
    late MinisignPublicKey otherKey;
    late String validSig;
    late String otherSig;
    late List<int> payload;

    setUpAll(() {
      dir = Directory.systemTemp.createTempSync('dt_sdk_sig');
      final Map<String, dynamic> fixture =
          jsonDecode(
                File(
                  inRepo(<String>[
                    'toolkit',
                    'dovetail_cli',
                    'test',
                    'fixtures',
                    'sdk-signatures.json',
                  ]),
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      payload = base64Decode(fixture['payload_base64'] as String);
      key = MinisignPublicKey.parse(fixture['public_key'] as String);
      otherKey = MinisignPublicKey.parse(
        fixture['foreign_public_key'] as String,
      );
      validSig = fixture['signature'] as String;
      otherSig = fixture['foreign_signature'] as String;
    });

    tearDownAll(() => dir.deleteSync(recursive: true));

    SdkChannel signed(Map<String, FetchedBody> responses) => SdkChannel(
      baseUrl: 'https://releases.example.com/',
      fetcher: _CannedFetcher(responses),
      releaseKey: key,
    );

    String tarballPath() => '/0.1.0/${SdkChannel.tarballName('0.1.0')}';

    Map<String, FetchedBody> validChannel({String? sig}) {
      final String tarball = tarballPath();
      return <String, FetchedBody>{
        tarball: FetchedBody(
          statusCode: 200,
          bytes: Uint8List.fromList(payload),
        ),
        '$tarball.sha256': FetchedBody(
          statusCode: 200,
          bytes: Uint8List.fromList(
            utf8.encode('${sha256.convert(payload)}\n'),
          ),
        ),
        '$tarball.minisig': FetchedBody(
          statusCode: 200,
          bytes: Uint8List.fromList(utf8.encode(sig ?? validSig)),
        ),
      };
    }

    Future<void> downloadWith(Map<String, FetchedBody> responses) async {
      final File target = File(p.join(dir.path, 'out.tar.gz'));
      await signed(responses).download('0.1.0', target);
    }

    test('a tarball with its minisig should install', () async {
      final File target = File(p.join(dir.path, 'out.tar.gz'));
      await signed(validChannel()).download('0.1.0', target);
      expect(target.readAsBytesSync(), payload);
    });

    test('public fixture signatures verify with their respective keys', () {
      for (final (String signature, MinisignPublicKey publicKey)
          in <(String, MinisignPublicKey)>[
            (validSig, key),
            (otherSig, otherKey),
          ]) {
        MinisignVerifier.verify(
          payload: Uint8List.fromList(payload),
          signature: MinisignSignature.parse(signature),
          publicKey: publicKey,
        );
      }
    });

    test(
      'a changed payload with a matching new hash still refuses its old signature',
      () async {
        final List<int> changed = utf8.encode('mirror replaced the payload');
        final Map<String, FetchedBody> responses = validChannel()
          ..[tarballPath()] = FetchedBody(
            statusCode: 200,
            bytes: Uint8List.fromList(changed),
          )
          ..['${tarballPath()}.sha256'] = FetchedBody(
            statusCode: 200,
            bytes: Uint8List.fromList(
              utf8.encode(sha256.convert(changed).toString()),
            ),
          );
        await expectLater(
          downloadWith(responses),
          throwsA(
            isA<UpdateFailure>().having(
              (UpdateFailure error) => error.message,
              'message',
              contains('does not match its signature'),
            ),
          ),
        );
      },
    );

    test(
      'a changed trusted comment refuses an otherwise valid signature',
      () async {
        final String changed = validSig.replaceFirst(
          'file:sdk-fixture.bin',
          'file:changed.bin',
        );
        await expectLater(
          downloadWith(validChannel(sig: changed)),
          throwsA(
            isA<UpdateFailure>().having(
              (UpdateFailure error) => error.message,
              'message',
              contains('trusted comment'),
            ),
          ),
        );
      },
    );

    test('a channel without the minisig should refuse', () async {
      final Map<String, FetchedBody> responses = validChannel()
        ..remove('${tarballPath()}.minisig');

      await expectLater(
        downloadWith(responses),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure error) => error.message,
            'message',
            contains('.minisig'),
          ),
        ),
      );
    });

    test('a tarball signed by another key should refuse', () async {
      // Uma assinatura de outra chave: o sha256 bate (o espelho serve o
      // arquivo certo), mas a assinatura não.
      await expectLater(
        downloadWith(validChannel(sig: otherSig)),
        throwsA(isA<UpdateFailure>()),
      );
    });
  });
}
