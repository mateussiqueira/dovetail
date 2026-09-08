import 'dart:io';
import 'dart:typed_data';

import 'package:dovetail_signer/dovetail_signer.dart' as signer;
import 'package:dovetail_updater/dovetail_updater.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _password = 'not-empty-and-not-guessed';

bool get _haveMinisign =>
    Process.runSync('which', <String>['minisign']).exitCode == 0;

void main() {
  late Directory root;
  late String artifact;
  late String secretKey;
  late String publicKeyPath;

  // O par protegido por senha, derivado UMA vez.
  //
  // `minisign -G` com senha deriva a chave por scrypt, e isso custa ~1,6s —
  // medido — em cada chamada. Sao nove testes e sete deles so precisam de "um
  // par valido": gerar em cada um eram ~13s de uma suite de ~32s, a mais longa
  // do pacote que domina o alvo `test`, ou seja o piso do portao depois do
  // escalonador. O par sai daqui e e COPIADO para o temp de cada teste, que
  // continua proprio: o isolamento e do diretorio, nao da derivacao.
  //
  // Os dois testes cuja MATERIA e a chave — o par sem senha, e a assinatura
  // conferida contra outra chave — continuam gerando de verdade, porque ali o
  // `-G` e o que esta sendo provado.
  late Directory shared;
  late String sharedSecret;
  late String sharedPublic;
  setUpAll(() async {
    shared = Directory.systemTemp.createTempSync('dovetail_release_key');
    sharedSecret = p.join(shared.path, 'update.key');
    sharedPublic = p.join(shared.path, 'update.pub');
    if (!_haveMinisign) {
      return;
    }
    final signer.ProcessOutcome outcome =
        await const signer.SystemProcessRunner().run('minisign', <String>[
          '-G',
          '-f',
          '-p',
          sharedPublic,
          '-s',
          sharedSecret,
        ], stdin: '$_password\n$_password\n');
    expect(outcome.succeeded, true, reason: outcome.stderr);
  });
  tearDownAll(() => shared.deleteSync(recursive: true));

  setUp(() {
    root = Directory.systemTemp.createTempSync('dovetail_release');
    artifact = p.join(root.path, 'client_2.1.0_universal.app.tar.gz');
    secretKey = p.join(root.path, 'update.key');
    publicKeyPath = p.join(root.path, 'update.pub');
    File(artifact).writeAsBytesSync(
      Uint8List.fromList(
        List<int>.generate(4096, (int index) => (index * 31) % 256),
      ),
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<void> generateKey({
    String? publicKey,
    String? privateKey,
    bool unencrypted = false,
  }) async {
    // O caso padrao — par protegido, nos caminhos padrao — e uma copia do
    // par compartilhado. Qualquer outra coisa gera de verdade.
    if (publicKey == null && privateKey == null && !unencrypted) {
      File(sharedSecret).copySync(secretKey);
      File(sharedPublic).copySync(publicKeyPath);
      return;
    }
    final signer.ProcessOutcome outcome =
        await const signer.SystemProcessRunner().run('minisign', <String>[
          '-G',
          '-f',
          if (unencrypted) '-W',
          '-p',
          publicKey ?? publicKeyPath,
          '-s',
          privateKey ?? secretKey,
        ], stdin: unencrypted ? null : '$_password\n$_password\n');
    expect(outcome.succeeded, true, reason: outcome.stderr);
  }

  Future<signer.UpdateSignature> signArtifact() =>
      const signer.UpdateSigner(runner: signer.SystemProcessRunner()).sign(
        artifactPath: artifact,
        secretKeyPath: secretKey,
        access: const signer.PasswordProtectedKey(_password),
        trustedComment: 'file:${p.basename(artifact)}',
      );

  MinisignPublicKey trustedKey([String? path]) =>
      MinisignPublicKey.parse(File(path ?? publicKeyPath).readAsStringSync());

  test(
    'the signer should produce what the updater accepts',
    () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      await generateKey();

      final signer.UpdateSignature produced = await signArtifact();
      final MinisignSignature parsed = MinisignSignature.parse(
        produced.content,
      );

      expect(
        parsed.keyIdHex,
        trustedKey().keyIdHex,
        reason: 'the client matches the key id before it spends a byte',
      );
      expect(
        () => MinisignVerifier.verify(
          payload: File(artifact).readAsBytesSync(),
          signature: parsed,
          publicKey: trustedKey(),
        ),
        returnsNormally,
        reason:
            'the signer drives the real minisign binary and the updater '
            'verifies in Dart; if these two ever disagree, every client '
            'rejects every release',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('the two implementations should read the same key id', () async {
    if (!_haveMinisign) {
      markTestSkipped('minisign is not installed');
      return;
    }
    await generateKey();

    final signer.UpdateSignature produced = await signArtifact();
    expect(
      produced.keyIdHex,
      MinisignSignature.parse(produced.content).keyIdHex,
      reason:
          'the signer reads the key id to name the release and the updater '
          'reads it to decide whether to trust the file',
    );
  });

  test('the two implementations should agree on prehashing', () async {
    if (!_haveMinisign) {
      markTestSkipped('minisign is not installed');
      return;
    }
    await generateKey();

    final signer.UpdateSignature produced = await signArtifact();
    expect(produced.algorithm, 'ED');
    expect(
      MinisignSignature.parse(produced.content).isPrehashed,
      produced.isPrehashed,
      reason:
          'both read the same two algorithm bytes; a disagreement means one '
          'hashes the artefact and the other signs it whole',
    );
  });

  test('the trusted comment should survive from signer to updater', () async {
    if (!_haveMinisign) {
      markTestSkipped('minisign is not installed');
      return;
    }
    await generateKey();

    final signer.UpdateSignature produced = await signArtifact();
    expect(
      MinisignSignature.parse(produced.content).trustedComment,
      produced.trustedComment,
    );
    expect(produced.trustedComment, contains('file:'));
  });

  test('the updater should reject a signature from another key', () async {
    if (!_haveMinisign) {
      markTestSkipped('minisign is not installed');
      return;
    }
    await generateKey();
    final signer.UpdateSignature produced = await signArtifact();

    final String otherPublic = p.join(root.path, 'other.pub');
    await generateKey(
      publicKey: otherPublic,
      privateKey: p.join(root.path, 'other.key'),
      unencrypted: true,
    );

    expect(
      () => MinisignVerifier.verify(
        payload: File(artifact).readAsBytesSync(),
        signature: MinisignSignature.parse(produced.content),
        publicKey: trustedKey(otherPublic),
      ),
      throwsA(
        isA<UpdateFailure>().having(
          (UpdateFailure failure) => failure.message,
          'message',
          contains('trusts'),
        ),
      ),
    );
  });

  test('the updater should reject a tampered artefact', () async {
    if (!_haveMinisign) {
      markTestSkipped('minisign is not installed');
      return;
    }
    await generateKey();
    final signer.UpdateSignature produced = await signArtifact();

    final Uint8List bytes = File(artifact).readAsBytesSync();
    bytes[2048] = bytes[2048] ^ 0xFF;

    expect(
      () => MinisignVerifier.verify(
        payload: bytes,
        signature: MinisignSignature.parse(produced.content),
        publicKey: trustedKey(),
      ),
      throwsA(
        isA<UpdateFailure>().having(
          (UpdateFailure failure) => failure.message,
          'message',
          contains('does not match'),
        ),
      ),
    );
  });

  test('a truncated download should be rejected, not padded', () async {
    if (!_haveMinisign) {
      markTestSkipped('minisign is not installed');
      return;
    }
    await generateKey();
    final signer.UpdateSignature produced = await signArtifact();

    expect(
      () => MinisignVerifier.verify(
        payload: Uint8List.sublistView(
          File(artifact).readAsBytesSync(),
          0,
          2048,
        ),
        signature: MinisignSignature.parse(produced.content),
        publicKey: trustedKey(),
      ),
      throwsA(isA<UpdateFailure>()),
    );
  });

  test('what the manifest carries should survive the round trip', () async {
    if (!_haveMinisign) {
      markTestSkipped('minisign is not installed');
      return;
    }
    await generateKey();
    final signer.UpdateSignature produced = await signArtifact();

    final UpdateManifest manifest = ManifestParser.parse(
      '{"version":"2.1.0","platforms":{"darwin-aarch64":'
      '{"url":"https://cdn.example.com/${p.basename(artifact)}",'
      '"signature":"${produced.wrappedForManifest}"}}}',
    );

    final MinisignSignature fromManifest = MinisignSignature.parse(
      manifest.releaseFor('darwin-aarch64').signature,
    );

    expect(fromManifest.keyIdHex, produced.keyIdHex);
    expect(
      () => MinisignVerifier.verify(
        payload: File(artifact).readAsBytesSync(),
        signature: fromManifest,
        publicKey: trustedKey(),
      ),
      returnsNormally,
      reason:
          'the manifest wraps the signature in a second layer of base64; a '
          'release that loses that layer is a release no client can read',
    );
    expect(
      const UpdatePolicy()
          .decide(installed: Version.parse('2.0.0'), manifest: manifest)
          .shouldUpdate,
      true,
    );
  });

  test(
    'the raw signature should also parse, not only the wrapped one',
    () async {
      if (!_haveMinisign) {
        markTestSkipped('minisign is not installed');
        return;
      }
      await generateKey();
      final signer.UpdateSignature produced = await signArtifact();

      final UpdateManifest manifest = ManifestParser.parse(
        '{"version":"2.1.0","platforms":{"darwin-aarch64":'
        '{"url":"https://cdn.example.com/a.tar.gz",'
        '"signature":${_jsonString(produced.content)}}}}',
      );

      expect(
        MinisignSignature.parse(
          manifest.releaseFor('darwin-aarch64').signature,
        ).keyIdHex,
        produced.keyIdHex,
        reason:
            'the installed park writes the wrapped form, but a hand-built '
            'manifest carries the raw one and both have to work',
      );
    },
  );
}

String _jsonString(String value) {
  final String escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\t', r'\t');
  return '"$escaped"';
}
