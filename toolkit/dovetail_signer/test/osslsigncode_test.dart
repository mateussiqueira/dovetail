import 'dart:io';

import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

bool get _hasOsslsigncode =>
    Process.runSync('which', <String>['osslsigncode']).exitCode == 0;

bool get _hasOpenssl =>
    Process.runSync('which', <String>['openssl']).exitCode == 0;

const String _minimalPortableExecutable = r'''
import struct, sys
mz = bytearray(0x40)
mz[0:2] = b'MZ'
struct.pack_into('<I', mz, 0x3C, 0x40)
opt = bytearray(0xF0)
struct.pack_into('<H', opt, 0, 0x20B)
struct.pack_into('<I', opt, 16, 0x1000)
struct.pack_into('<Q', opt, 24, 0x140000000)
struct.pack_into('<I', opt, 32, 0x1000)
struct.pack_into('<I', opt, 36, 0x200)
struct.pack_into('<H', opt, 68, 6)
struct.pack_into('<I', opt, 80, 0x2000)
struct.pack_into('<I', opt, 84, 0x200)
struct.pack_into('<H', opt, 92, 3)
struct.pack_into('<I', opt, 108, 16)
coff = struct.pack('<HHIIIHH', 0x8664, 1, 0, 0, 0, len(opt), 0x022)
sec = struct.pack('<8sIIIIIIHHI', b'.text\x00\x00\x00', 0x1000, 0x1000,
                  0x200, 0x200, 0, 0, 0, 0, 0x60000020)
head = bytes(mz) + b'PE\x00\x00' + coff + bytes(opt) + sec
head += b'\x00' * (0x200 - len(head))
open(sys.argv[1], 'wb').write(head + b'\x90' * 0x200)
''';

void main() {
  late Directory root;
  const ProcessRunner runner = SystemProcessRunner();

  setUp(() => root = Directory.systemTemp.createTempSync('osslsign'));
  tearDown(() => root.deleteSync(recursive: true));

  String at(String name) => p.join(root.path, name);

  bool makeCertificate() {
    if (!_hasOpenssl) {
      return false;
    }
    return Process.runSync('openssl', <String>[
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
          '/CN=Dovetail Test Publisher',
          '-addext',
          'extendedKeyUsage=codeSigning',
        ]).exitCode ==
        0;
  }

  bool makePortableExecutable(String name) {
    final File script = File(at('mkpe.py'))
      ..writeAsStringSync(_minimalPortableExecutable);
    return Process.runSync('python3', <String>[
          script.path,
          at(name),
        ]).exitCode ==
        0;
  }

  group('the arguments it builds', () {
    test('a PEM pair should reach -certs and -key', () {
      expect(
        const Osslsigncode(runner: runner).argumentsFor(
          const OsslsigncodeRequest(
            certificatePath: '/c.pem',
            privateKeyPath: '/k.pem',
            timestampUrl: 'http://timestamp.digicert.com',
            programName: 'Demo',
          ),
          input: '/in.exe',
          output: '/out.exe',
        ),
        <String>[
          'sign',
          '-certs',
          '/c.pem',
          '-key',
          '/k.pem',
          '-h',
          'sha256',
          '-ts',
          'http://timestamp.digicert.com',
          '-n',
          'Demo',
          '-in',
          '/in.exe',
          '-out',
          '/out.exe',
        ],
      );
    });

    test('a PKCS#12 bundle should reach -pkcs12 and -pass', () {
      expect(
        const OsslsigncodeRequest(
          certificatePath: '/bundle.pfx',
          password: 'secret',
          timestampUrl: 'http://t',
        ).credentialArguments(),
        <String>['-pkcs12', '/bundle.pfx', '-pass', 'secret'],
      );
    });

    test('a bundle with no password should refuse, not prompt', () {
      expect(
        () => const OsslsigncodeRequest(
          certificatePath: '/bundle.pfx',
          timestampUrl: 'http://t',
        ).credentialArguments(),
        throwsA(
          isA<SigningFailure>().having(
            (SigningFailure failure) => failure.remedy,
            'remedy',
            contains('never finishes'),
          ),
        ),
        reason:
            'osslsigncode prompts on a terminal, so in a pipeline a missing '
            'password is a build that hangs rather than one that fails',
      );
    });

    test('no timestamp should be refused, with no default supplied', () {
      expect(
        () => const Osslsigncode(runner: runner).argumentsFor(
          const OsslsigncodeRequest(
            certificatePath: '/c.pem',
            privateKeyPath: '/k.pem',
            timestampUrl: '  ',
          ),
          input: '/in.exe',
          output: '/out.exe',
        ),
        throwsA(
          isA<SigningFailure>().having(
            (SigningFailure failure) => failure.remedy,
            'remedy',
            contains('expires'),
          ),
        ),
      );
    });

    test('signing in place should be refused before the file is opened', () {
      expect(
        () => const Osslsigncode(runner: runner).argumentsFor(
          const OsslsigncodeRequest(
            certificatePath: '/c.pem',
            privateKeyPath: '/k.pem',
            timestampUrl: 'http://t',
          ),
          input: '/dist/app.exe',
          output: '/dist/./app.exe',
        ),
        throwsA(
          isA<SigningFailure>().having(
            (SigningFailure failure) => failure.remedy,
            'remedy',
            contains('truncates'),
          ),
        ),
      );
    });
  });

  group('what it agrees to sign', () {
    test('an archive should be refused by name', () async {
      File(at('build.zip')).writeAsStringSync('x');

      await expectLater(
        const Osslsigncode(runner: runner).sign(
          const OsslsigncodeRequest(
            certificatePath: '/c.pem',
            privateKeyPath: '/k.pem',
            timestampUrl: 'http://t',
          ),
          at('build.zip'),
        ),
        throwsA(
          isA<SigningFailure>().having(
            (SigningFailure failure) => failure.message,
            'message',
            contains('.zip'),
          ),
        ),
      );
    });

    test('an absent artefact should be refused', () async {
      await expectLater(
        const Osslsigncode(runner: runner).sign(
          const OsslsigncodeRequest(
            certificatePath: '/c.pem',
            privateKeyPath: '/k.pem',
            timestampUrl: 'http://t',
          ),
          at('missing.exe'),
        ),
        throwsA(isA<SigningFailure>()),
      );
    });
  });

  group('against the real osslsigncode, on this machine', () {
    test(
      'a PE signed here should verify here',
      () async {
        if (!_hasOsslsigncode || !makeCertificate()) {
          markTestSkipped('osslsigncode and openssl are needed');
          return;
        }
        if (!makePortableExecutable('app.exe')) {
          markTestSkipped('python3 is needed to lay down a PE header');
          return;
        }

        final int before = File(at('app.exe')).lengthSync();

        await const Osslsigncode(runner: runner).sign(
          OsslsigncodeRequest(
            certificatePath: at('cert.pem'),
            privateKeyPath: at('key.pem'),
            timestampUrl: 'http://timestamp.digicert.com',
            programName: 'Dovetail Demo',
          ),
          at('app.exe'),
        );

        expect(
          File(at('app.exe')).lengthSync(),
          greaterThan(before),
          reason: 'the certificate table is appended to the PE',
        );
        expect(
          await const Osslsigncode(
            runner: runner,
          ).verify(at('app.exe'), caFile: at('cert.pem')),
          true,
          reason:
              'Windows code signing without a Windows machine is the whole '
              'point; a signature this cannot verify is not one',
        );
        expect(
          File('${at('app.exe')}.signing').existsSync(),
          false,
          reason:
              'the staged file is moved over the original, never left beside',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'a wrong certificate should fail verification, not pass it',
      () async {
        if (!_hasOsslsigncode || !makeCertificate()) {
          markTestSkipped('osslsigncode and openssl are needed');
          return;
        }
        if (!makePortableExecutable('app.exe')) {
          markTestSkipped('python3 is needed to lay down a PE header');
          return;
        }

        await const Osslsigncode(runner: runner).sign(
          OsslsigncodeRequest(
            certificatePath: at('cert.pem'),
            privateKeyPath: at('key.pem'),
            timestampUrl: 'http://timestamp.digicert.com',
          ),
          at('app.exe'),
        );

        Process.runSync('openssl', <String>[
          'req',
          '-x509',
          '-newkey',
          'rsa:2048',
          '-keyout',
          at('other.key'),
          '-out',
          at('other.pem'),
          '-days',
          '1',
          '-nodes',
          '-subj',
          '/CN=Someone Else',
        ]);

        expect(
          await const Osslsigncode(
            runner: runner,
          ).verify(at('app.exe'), caFile: at('other.pem')),
          false,
          reason: 'a verifier that passes any certificate proves nothing',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'an unsigned PE should not verify',
      () async {
        if (!_hasOsslsigncode || !makeCertificate()) {
          markTestSkipped('osslsigncode and openssl are needed');
          return;
        }
        if (!makePortableExecutable('bare.exe')) {
          markTestSkipped('python3 is needed to lay down a PE header');
          return;
        }

        expect(
          await const Osslsigncode(
            runner: runner,
          ).verify(at('bare.exe'), caFile: at('cert.pem')),
          false,
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
