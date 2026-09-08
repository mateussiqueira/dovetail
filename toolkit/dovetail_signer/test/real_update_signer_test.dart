import 'dart:convert';
import 'dart:io';

import 'package:dovetail_signer/dovetail_signer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _password = 'a-password-that-is-not-empty';

bool get _haveMinisign =>
    Process.runSync('which', <String>['minisign']).exitCode == 0;

void main() {
  late Directory root;
  late String artifact;
  late String secretKey;
  late String publicKey;

  // Generated once for the whole file, then copied into each test's own
  // directory. A password-protected minisign key costs about six seconds
  // because scrypt is meant to, and five tests each paying that put the file
  // within reach of the thirty-second default timeout whenever the machine
  // was busy — which is exactly when the whole suite runs. What the tests are
  // about is the signing, not the key generation, and every test still gets
  // its own copy of the bytes.
  Directory? shared;

  const UpdateSigner sut = UpdateSigner(runner: SystemProcessRunner());

  setUpAll(() async {
    if (!_haveMinisign) {
      return;
    }
    final Directory made = Directory.systemTemp.createTempSync(
      'dovetail_usign_keys',
    );
    shared = made;
    for (final (String name, List<String> extra) key
        in <(String, List<String>)>[
          ('password', <String>[]),
          ('unencrypted', <String>['-W']),
        ]) {
      final ProcessOutcome outcome = await const SystemProcessRunner()
          .run('minisign', <String>[
            '-G',
            '-f',
            ...key.$2,
            '-p',
            p.join(made.path, '${key.$1}.pub'),
            '-s',
            p.join(made.path, '${key.$1}.key'),
          ], stdin: key.$2.isEmpty ? '$_password\n$_password\n' : null);
      expect(outcome.succeeded, true, reason: outcome.stderr);
    }
  });

  tearDownAll(() => shared?.deleteSync(recursive: true));

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_usign');
    artifact = p.join(root.path, 'app.tar.gz');
    secretKey = p.join(root.path, 'sec.key');
    publicKey = p.join(root.path, 'pub.key');
    File(artifact).writeAsStringSync('the bytes a client would download');
  });

  tearDown(() => root.deleteSync(recursive: true));

  void useKey(String which) {
    final Directory made = shared!;
    File(p.join(made.path, '$which.key')).copySync(secretKey);
    File(p.join(made.path, '$which.pub')).copySync(publicKey);
  }

  Future<void> generateKeyWithPassword() async => useKey('password');

  Future<void> generateUnencryptedKey() async => useKey('unencrypted');

  group('argumentsFor', () {
    test('should name the signature file rather than trust the default', () {
      final List<String> arguments = sut.argumentsFor(
        artifactPath: '/out/app.tar.gz',
        secretKeyPath: '/keys/sec.key',
        signaturePath: '/out/app.tar.gz.minisig',
        trustedComment: 'timestamp:1 file:app.tar.gz',
      );
      expect(
        arguments,
        containsAllInOrder(<String>['-S', '-s', '/keys/sec.key']),
      );
      expect(
        arguments,
        containsAllInOrder(<String>['-x', '/out/app.tar.gz.minisig']),
      );
      expect(arguments.last, '/out/app.tar.gz');
    });

    test(
      'should carry the trusted comment, which binds it to the signature',
      () {
        expect(
          sut.argumentsFor(
            artifactPath: 'a',
            secretKeyPath: 'k',
            signaturePath: 's',
            trustedComment: 'file:a',
          ),
          containsAllInOrder(<String>['-t', 'file:a']),
        );
      },
    );
  });

  group('refusals that need no minisign', () {
    test('should refuse an artefact that is not there', () async {
      await expectLater(
        sut.sign(
          artifactPath: p.join(root.path, 'absent.tar.gz'),
          secretKeyPath: secretKey,
          access: const PasswordProtectedKey(_password),
        ),
        throwsA(isA<SigningFailure>()),
      );
    });

    test('should refuse a key that is not there', () async {
      await expectLater(
        sut.sign(
          artifactPath: artifact,
          secretKeyPath: p.join(root.path, 'absent.key'),
          access: const PasswordProtectedKey(_password),
        ),
        throwsA(
          isA<SigningFailure>().having(
            (SigningFailure failure) => failure.remedy,
            'remedy',
            contains('every client already trusts'),
          ),
        ),
      );
    });

    test('an empty password should be fatal, never assumed', () async {
      File(secretKey).writeAsStringSync('placeholder');
      await expectLater(
        sut.sign(
          artifactPath: artifact,
          secretKeyPath: secretKey,
          access: const PasswordProtectedKey(''),
        ),
        throwsA(
          isA<SigningFailure>().having(
            (SigningFailure failure) => failure.message,
            'message',
            contains('empty'),
          ),
        ),
      );
    });
  });

  group('against the real minisign', () {
    test('should sign with a password-protected key', () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      await generateKeyWithPassword();

      final UpdateSignature signature = await sut.sign(
        artifactPath: artifact,
        secretKeyPath: secretKey,
        access: const PasswordProtectedKey(_password),
        trustedComment: 'file:app.tar.gz',
      );

      expect(File(signature.signaturePath).existsSync(), true);
      expect(signature.content, contains('untrusted comment:'));
      expect(signature.content, contains('trusted comment:'));
      expect(signature.trustedComment, startsWith('file:app.tar.gz'));
      expect(signature.keyIdHex, hasLength(16));
      expect(
        signature.algorithm,
        'ED',
        reason: 'modern minisign prehashes; the legacy format writes Ed',
      );
      expect(signature.isPrehashed, true);
    });

    test('the real minisign should verify what this signed', () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      await generateKeyWithPassword();

      final UpdateSignature signature = await sut.sign(
        artifactPath: artifact,
        secretKeyPath: secretKey,
        access: const PasswordProtectedKey(_password),
      );

      final ProcessResult verified = Process.runSync('minisign', <String>[
        '-V',
        '-p',
        publicKey,
        '-x',
        signature.signaturePath,
        '-m',
        artifact,
      ]);
      expect(verified.exitCode, 0, reason: verified.stderr.toString());
    });

    test(
      'a wrong password should surface, not produce a silent nothing',
      () async {
        if (!_haveMinisign) {
          markTestSkipped('minisign is not installed');
          return;
        }
        await generateKeyWithPassword();

        await expectLater(
          sut.sign(
            artifactPath: artifact,
            secretKeyPath: secretKey,
            access: const PasswordProtectedKey('the-wrong-one'),
          ),
          throwsA(
            isA<SigningFailure>().having(
              (SigningFailure failure) => failure.remedy,
              'remedy',
              contains('Wrong password'),
            ),
          ),
        );
        expect(File('$artifact.minisig').existsSync(), false);
      },
    );

    test('should sign with an unencrypted key when told it is one', () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      await generateUnencryptedKey();

      final UpdateSignature signature = await sut.sign(
        artifactPath: artifact,
        secretKeyPath: secretKey,
        access: const UnencryptedKey(),
      );
      expect(File(signature.signaturePath).existsSync(), true);
    });

    test(
      'a password key signed as unencrypted should fail loudly',
      () async {
        if (!_haveMinisign) {
          markTestSkipped('minisign is not installed');
          return;
        }
        await generateKeyWithPassword();

        await expectLater(
          sut.sign(
            artifactPath: artifact,
            secretKeyPath: secretKey,
            access: const UnencryptedKey(),
          ),
          throwsA(isA<SigningFailure>()),
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('changing one byte should invalidate the signature', () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      await generateUnencryptedKey();

      final UpdateSignature signature = await sut.sign(
        artifactPath: artifact,
        secretKeyPath: secretKey,
        access: const UnencryptedKey(),
      );
      File(artifact).writeAsStringSync('tampered');

      expect(
        Process.runSync('minisign', <String>[
          '-V',
          '-p',
          publicKey,
          '-x',
          signature.signaturePath,
          '-m',
          artifact,
        ]).exitCode,
        isNot(0),
      );
    });

    test('the wrapped form should be what a manifest carries', () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      await generateUnencryptedKey();

      final UpdateSignature signature = await sut.sign(
        artifactPath: artifact,
        secretKeyPath: secretKey,
        access: const UnencryptedKey(),
      );

      expect(
        utf8.decode(base64.decode(signature.wrappedForManifest)),
        signature.content,
      );
    });
  });
}
