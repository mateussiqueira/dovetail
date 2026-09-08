import 'dart:convert';
import 'dart:typed_data';

import 'package:dovetail_updater/src/update_failure.dart';

const int _keyIdLength = 8;
const int _publicKeyLength = 32;
const String _untrustedPrefix = 'untrusted comment:';

final class MinisignPublicKey {
  const MinisignPublicKey({
    required this.algorithm,
    required this.keyId,
    required this.key,
  });

  factory MinisignPublicKey.parse(String encoded) {
    final String text = unwrap(encoded);
    final List<String> lines = text
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList();

    if (lines.length < 2) {
      throw const UpdateFailure(
        'a minisign public key needs a comment line and a key line.',
      );
    }

    final Uint8List raw = _decodeBase64(lines.last, 'public key');
    if (raw.length != 2 + _keyIdLength + _publicKeyLength) {
      throw UpdateFailure(
        'a minisign public key is 42 bytes; this one is ${raw.length}.',
      );
    }

    return MinisignPublicKey(
      algorithm: _algorithm(raw),
      keyId: Uint8List.sublistView(raw, 2, 2 + _keyIdLength),
      key: Uint8List.sublistView(raw, 2 + _keyIdLength),
    );
  }

  final String algorithm;
  final Uint8List keyId;
  final Uint8List key;

  String get keyIdHex => keyId.reversed
      .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  /// Os dois primeiros bytes da chave, recusados quando não são o algoritmo
  /// minisign — o `ascii.decode` padrão lança FormatException para bytes fora
  /// do ASCII, e um cliente não pode morrer com um corpo controlado.
  static String _algorithm(Uint8List raw) {
    final String algorithm = ascii.decode(
      raw.sublist(0, 2),
      allowInvalid: true,
    );
    if (algorithm == 'Ed' || algorithm == 'ED') {
      return algorithm;
    }
    throw const UpdateFailure('the signature algorithm is not Ed/ED.');
  }

  static String unwrap(String encoded) {
    final String trimmed = encoded.trim();
    if (trimmed.startsWith(_untrustedPrefix)) {
      return trimmed;
    }

    final String decoded;
    try {
      decoded = utf8.decode(base64.decode(trimmed.replaceAll('\n', '')));
    } on Object {
      throw const UpdateFailure(
        'the value is neither minisign text nor base64 around it.',
        remedy:
            'Tauri stores both the public key and the signature as base64 on '
            'top of the standard minisign text. A raw minisign signature will '
            'not be accepted by clients already in the field.',
      );
    }

    if (!decoded.trimLeft().startsWith(_untrustedPrefix)) {
      throw const UpdateFailure(
        'the base64 decoded to something that is not minisign text.',
      );
    }
    return decoded;
  }

  static Uint8List _decodeBase64(String line, String what) {
    try {
      return base64.decode(line);
    } on FormatException {
      throw UpdateFailure('the $what line is not valid base64.');
    }
  }
}
