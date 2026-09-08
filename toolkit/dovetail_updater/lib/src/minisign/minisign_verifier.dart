import 'dart:convert';
import 'dart:typed_data';

import 'package:dovetail_updater/src/minisign/minisign_public_key.dart';
import 'package:dovetail_updater/src/minisign/minisign_signature.dart';
import 'package:dovetail_updater/src/update_failure.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:pointycastle/digests/blake2b.dart';

abstract final class MinisignVerifier {
  static void verify({
    required Uint8List payload,
    required MinisignSignature signature,
    required MinisignPublicKey publicKey,
  }) {
    if (!_sameKeyId(signature.keyId, publicKey.keyId)) {
      throw UpdateFailure(
        'the signature was made by key ${signature.keyIdHex} but the app '
        'trusts ${publicKey.keyIdHex}.',
        remedy:
            'A build signed with the wrong private key produces artefacts no '
            'installed client accepts. Fail here rather than in the field.',
      );
    }

    final Uint8List message = signature.isPrehashed
        ? blake2b512(payload)
        : payload;

    final ed.PublicKey key = ed.PublicKey(publicKey.key);
    if (!ed.verify(key, message, signature.signature)) {
      throw const UpdateFailure(
        'the artefact does not match its signature.',
        remedy: 'Nothing is installed. The download was altered or truncated.',
      );
    }

    final Uint8List bound = Uint8List.fromList(<int>[
      ...signature.signature,
      ...utf8.encode(signature.trustedComment),
    ]);
    if (!ed.verify(key, bound, signature.globalSignature)) {
      throw const UpdateFailure(
        'the trusted comment is not bound to this signature.',
        remedy:
            'The comment carries the timestamp and the file name. A signature '
            'replayed onto another file would land here.',
      );
    }
  }

  static Uint8List blake2b512(Uint8List payload) {
    final Blake2bDigest digest = Blake2bDigest(digestSize: 64);
    digest.update(payload, 0, payload.length);
    final Uint8List out = Uint8List(64);
    digest.doFinal(out, 0);
    return out;
  }

  static bool _sameKeyId(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      return false;
    }
    int difference = 0;
    for (int index = 0; index < a.length; index++) {
      difference |= a[index] ^ b[index];
    }
    return difference == 0;
  }
}
