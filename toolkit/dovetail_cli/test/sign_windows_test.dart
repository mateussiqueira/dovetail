import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:dovetail_cli/dovetail_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

bool get _hasOsslsigncode =>
    Process.runSync('which', <String>['osslsigncode']).exitCode == 0;

bool get _hasOpenssl =>
    Process.runSync('which', <String>['openssl']).exitCode == 0;

void main() {
  late Directory root;
  late CommandRunner<int> runner;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_signwin');
    runner = CommandRunner<int>('dovetail', 'test')..addCommand(SignCommand());
  });

  tearDown(() => root.deleteSync(recursive: true));

  String at(String name) => p.join(root.path, name);

  group('the credentials it asks for off Windows', () {
    test('should name the certificate file, not a store thumbprint', () {
      expect(
        OsslsigncodeCredentials.keyPair.members.map(
          (Credential credential) => credential.name,
        ),
        contains('WINDOWS_CERTIFICATE_FILE'),
        reason:
            'a thumbprint names a certificate in the Windows store, which is '
            'the one thing a machine that is not Windows does not have',
      );
    });

    test('should still insist on a timestamp server', () {
      expect(
        OsslsigncodeCredentials.keyPair.members.map(
          (Credential credential) => credential.name,
        ),
        contains('WINDOWS_TIMESTAMP_URL'),
      );
    });
  });

  group('nested entitlements', () {
    Future<int?> signMacos(List<String> extra) async {
      Directory(at('Example.app')).createSync();
      return runner.run(<String>[
        'sign',
        '--target',
        'macos',
        '--bundle',
        at('Example.app'),
        ...extra,
      ]);
    }

    test('a pair without an equals sign should be refused', () async {
      await expectLater(
        signMacos(<String>['--entitlements-for', 'Contents/Helpers/daemon']),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('relative/path='),
          ),
        ),
      );
    });

    test('an entitlements file that is not there should be refused', () async {
      await expectLater(
        signMacos(<String>[
          '--entitlements-for',
          'Contents/Helpers/daemon=${at('absent.plist')}',
        ]),
        throwsA(
          isA<UsageException>().having(
            (UsageException error) => error.message,
            'message',
            contains('no entitlements file'),
          ),
        ),
      );
    });

    test('the same nested path twice should be refused', () async {
      File(at('a.plist')).writeAsStringSync('<plist/>');
      File(at('b.plist')).writeAsStringSync('<plist/>');

      await expectLater(
        signMacos(<String>[
          '--entitlements-for',
          'Contents/Helpers/daemon=${at('a.plist')}',
          '--entitlements-for',
          'Contents/Helpers/daemon=${at('b.plist')}',
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

    test('a well-formed pair should reach the request', () {
      const MacosSigningRequest request = MacosSigningRequest(
        bundlePath: '/tmp/Example.app',
        identity: '-',
        appEntitlements: '/tmp/app.plist',
        entitlementsByRelativePath: <String, String>{
          'Contents/Helpers/daemon': '/tmp/daemon.plist',
        },
      );

      expect(
        request.entitlementsFor(
          const SignTarget(
            path: '/tmp/Example.app/Contents/Helpers/daemon',
            isExecutable: true,
          ),
        ),
        '/tmp/daemon.plist',
        reason:
            'a privileged helper needs its own entitlements, and giving it the '
            "app's is how a daemon ends up with the app's sandbox",
      );
      expect(
        request.entitlementsFor(
          const SignTarget(path: '/tmp/Example.app', isExecutable: true),
        ),
        '/tmp/app.plist',
      );
    });
  });

  group('signing a real PE through the command', () {
    test(
      'should sign it and leave a signature that verifies',
      () async {
        if (!_hasOsslsigncode || !_hasOpenssl) {
          markTestSkipped('osslsigncode and openssl are needed');
          return;
        }
        if (Process.runSync('openssl', <String>[
              'req',
              '-x509',
              '-newkey',
              'rsa:2048',
              '-keyout',
              at('key.pem'),
              '-out',
              at('cert.pem'),
              '-days',
              '1',
              '-nodes',
              '-subj',
              '/CN=Dovetail CLI Test',
              '-addext',
              'extendedKeyUsage=codeSigning',
            ]).exitCode !=
            0) {
          markTestSkipped('openssl could not make a certificate');
          return;
        }

        final File pe = File(at('setup.exe'))..writeAsBytesSync(_minimalPe());
        final int before = pe.lengthSync();

        expect(
          await runner.run(<String>[
            'sign',
            '--target',
            'windows',
            '--file',
            pe.path,
            '--program-name',
            'Dovetail Demo',
            '--certificate',
            at('cert.pem'),
            '--private-key',
            at('key.pem'),
            '--timestamp-url',
            'http://timestamp.digicert.com',
          ]),
          0,
        );

        expect(pe.lengthSync(), greaterThan(before));
        expect(
          await const Osslsigncode(
            runner: SystemProcessRunner(),
          ).verify(pe.path, caFile: at('cert.pem')),
          true,
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

Uint8List _minimalPe() {
  const int headerSize = 0x200;
  final Uint8List bytes = Uint8List(headerSize * 2);
  final ByteData view = ByteData.sublistView(bytes);

  bytes[0] = 0x4D;
  bytes[1] = 0x5A;
  view.setUint32(0x3C, 0x40, Endian.little);

  const int pe = 0x40;
  bytes.setRange(pe, pe + 4, <int>[0x50, 0x45, 0, 0]);

  const int coff = pe + 4;
  view
    ..setUint16(coff, 0x8664, Endian.little)
    ..setUint16(coff + 2, 1, Endian.little)
    ..setUint16(coff + 16, 0xF0, Endian.little)
    ..setUint16(coff + 18, 0x0022, Endian.little);

  const int optional = coff + 20;
  view
    ..setUint16(optional, 0x020B, Endian.little)
    ..setUint32(optional + 16, 0x1000, Endian.little)
    ..setUint64(optional + 24, 0x140000000, Endian.little)
    ..setUint32(optional + 32, 0x1000, Endian.little)
    ..setUint32(optional + 36, 0x200, Endian.little)
    ..setUint16(optional + 68, 6, Endian.little)
    ..setUint32(optional + 80, 0x2000, Endian.little)
    ..setUint32(optional + 84, headerSize, Endian.little)
    ..setUint16(optional + 92, 3, Endian.little)
    ..setUint32(optional + 108, 16, Endian.little);

  const int section = optional + 0xF0;
  bytes.setRange(section, section + 8, '.text\u0000\u0000\u0000'.codeUnits);
  view
    ..setUint32(section + 8, 0x1000, Endian.little)
    ..setUint32(section + 12, 0x1000, Endian.little)
    ..setUint32(section + 16, headerSize, Endian.little)
    ..setUint32(section + 20, headerSize, Endian.little)
    ..setUint32(section + 36, 0x60000020, Endian.little);

  bytes.fillRange(headerSize, bytes.length, 0x90);
  return bytes;
}
