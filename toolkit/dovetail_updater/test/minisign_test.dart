import 'dart:convert';
import 'dart:typed_data';

import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:test/test.dart';

// Uma chave publica de exemplo, gerada pelo `minisign -G`, embrulhada em
// base64 como o Tauri escreve no `tauri.conf.json`. Era a chave de producao de
// um produto real, e uma publica nao e segredo — mas ela nomeava um projeto
// privado dentro de um repositorio aberto, e o teste ensina igual com um par
// de exemplo.
const String _wrappedPublicKey =
    'dW50cnVzdGVkIGNvbW1lbnQ6IG1pbmlzaWduIHB1YmxpYyBrZXkgOUUzQzJDMUI2QjQz'
    'NzFBQgpSV1NyY1VOckd5dzhuZ2FLbGdlYlk1ZjgycStnaVBWNEtlcWNMeVpFUzFoWXE2'
    'N0VvMmNlUkNmVAo=';

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

const String _payloadBase64 = 'ZG92ZXRhaWwgdXBkYXRlIHBheWxvYWQ=';

Uint8List get _payload => base64.decode(_payloadBase64);

String get _doubleEncodedSignature =>
    base64.encode(utf8.encode(_referenceSignature));

void main() {
  group('the wrapped public key form Tauri writes', () {
    test('should decode through the double base64 Tauri writes', () {
      final MinisignPublicKey sut = MinisignPublicKey.parse(_wrappedPublicKey);

      expect(sut.algorithm, 'Ed');
      expect(sut.key.length, 32);
    });

    test('should carry the key id its own comment declares', () {
      final MinisignPublicKey sut = MinisignPublicKey.parse(_wrappedPublicKey);

      expect(sut.keyIdHex, '9E3C2C1B6B4371AB');
    });

    test(
      'should also accept plain minisign text, not only the wrapped form',
      () {
        final MinisignPublicKey sut = MinisignPublicKey.parse(
          _referencePublicKey,
        );

        expect(sut.keyIdHex, '9104FC85BB0FC321');
      },
    );

    test(
      'should refuse something that is neither text nor base64 around it',
      () {
        expect(
          () => MinisignPublicKey.parse('not a key'),
          throwsA(
            isA<UpdateFailure>().having(
              (UpdateFailure failure) => failure.remedy,
              'remedy',
              contains('already in the field'),
            ),
          ),
        );
      },
    );
  });

  group('a signature produced by the reference minisign tool', () {
    test('should parse into its four parts', () {
      final MinisignSignature sut = MinisignSignature.parse(
        _referenceSignature,
      );

      expect(sut.signature.length, 64);
      expect(sut.globalSignature.length, 64);
      expect(sut.trustedComment, contains('file:small.bin'));
      expect(sut.keyIdHex, '9104FC85BB0FC321');
    });

    test(
      'should report itself as prehashed, which modern minisign defaults to',
      () {
        final MinisignSignature sut = MinisignSignature.parse(
          _referenceSignature,
        );

        expect(sut.algorithm, 'ED');
        expect(sut.isPrehashed, true);
      },
    );

    test('should verify against the payload the tool signed', () {
      MinisignVerifier.verify(
        payload: _payload,
        signature: MinisignSignature.parse(_referenceSignature),
        publicKey: MinisignPublicKey.parse(_referencePublicKey),
      );
    });

    test(
      'should verify the same way when wrapped in base64, as Tauri stores it',
      () {
        MinisignVerifier.verify(
          payload: _payload,
          signature: MinisignSignature.parse(_doubleEncodedSignature),
          publicKey: MinisignPublicKey.parse(_referencePublicKey),
        );
      },
    );

    test('should refuse a payload with a single byte changed', () {
      final Uint8List tampered = Uint8List.fromList(_payload)
        ..[0] = _payload[0] ^ 0x01;

      expect(
        () => MinisignVerifier.verify(
          payload: tampered,
          signature: MinisignSignature.parse(_referenceSignature),
          publicKey: MinisignPublicKey.parse(_referencePublicKey),
        ),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.message,
            'message',
            contains('does not match its signature'),
          ),
        ),
      );
    });

    test('should refuse a key that did not make it', () {
      expect(
        () => MinisignVerifier.verify(
          payload: _payload,
          signature: MinisignSignature.parse(_referenceSignature),
          publicKey: MinisignPublicKey.parse(_wrappedPublicKey),
        ),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.message,
            'message',
            allOf(contains('9104FC85BB0FC321'), contains('9E3C2C1B6B4371AB')),
          ),
        ),
      );
    });

    test('should refuse a trusted comment that was edited after signing', () {
      final String edited = _referenceSignature.replaceFirst(
        'file:small.bin',
        'file:malware.exe',
      );

      expect(
        () => MinisignVerifier.verify(
          payload: _payload,
          signature: MinisignSignature.parse(edited),
          publicKey: MinisignPublicKey.parse(_referencePublicKey),
        ),
        throwsA(
          isA<UpdateFailure>().having(
            (UpdateFailure failure) => failure.message,
            'message',
            contains('not bound to this signature'),
          ),
        ),
        reason:
            'Tauri never checks this, so a signature could be replayed onto '
            'another file name without the client noticing',
      );
    });

    test('should refuse a signature block of the wrong length', () {
      final String truncated = _referenceSignature.replaceFirst(
        RegExp(r'^RUQ.*$', multiLine: true),
        base64.encode(Uint8List(20)),
      );

      expect(
        () => MinisignSignature.parse(truncated),
        throwsA(isA<UpdateFailure>()),
      );
    });

    test('should refuse an algorithm that is not Ed/ED, not crash on it', () {
      // O bloco (74 bytes) com os dois primeiros bytes fora do ASCII: o
      // ascii.decode padrão lançaria FormatException, e um cliente não pode
      // morrer com um corpo que o atacante controla.
      final Uint8List block = base64.decode(
        RegExp(
          r'^RUQ.*$',
          multiLine: true,
        ).firstMatch(_referenceSignature)!.group(0)!,
      );
      block[0] = 0xFF;
      block[1] = 0xFF;
      final String poisoned = _referenceSignature.replaceFirst(
        RegExp(r'^RUQ.*$', multiLine: true),
        base64.encode(block),
      );

      expect(
        () => MinisignSignature.parse(poisoned),
        throwsA(isA<UpdateFailure>()),
      );
    });

    test('should refuse a public key whose algorithm is not Ed/ED', () {
      final Uint8List key = base64.decode(
        RegExp(
          r'^RWQ.*$',
          multiLine: true,
        ).firstMatch(_referencePublicKey)!.group(0)!,
      );
      key[0] = 0xFF;
      key[1] = 0xFF;
      final String poisoned = _referencePublicKey.replaceFirst(
        RegExp(r'^RWQ.*$', multiLine: true),
        base64.encode(key),
      );

      expect(
        () => MinisignPublicKey.parse(poisoned),
        throwsA(isA<UpdateFailure>()),
      );
    });

    test('should refuse a file that is missing the trusted comment', () {
      final String withoutComment = _referenceSignature
          .split('\n')
          .where((String line) => !line.startsWith('trusted comment:'))
          .join('\n');

      expect(
        () => MinisignSignature.parse(withoutComment),
        throwsA(isA<UpdateFailure>()),
      );
    });
  });

  test(
    'blake2b512 should produce the digest length minisign prehashes with',
    () {
      expect(MinisignVerifier.blake2b512(_payload).length, 64);
    },
  );
}
