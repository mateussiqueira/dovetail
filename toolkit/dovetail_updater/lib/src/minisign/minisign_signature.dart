import 'dart:convert';
import 'dart:typed_data';

import 'package:dovetail_updater/src/minisign/minisign_public_key.dart';
import 'package:dovetail_updater/src/update_failure.dart';

const int _keyIdLength = 8;
const int _signatureLength = 64;
const String _trustedPrefix = 'trusted comment:';

final class MinisignSignature {
  const MinisignSignature({
    required this.algorithm,
    required this.keyId,
    required this.signature,
    required this.trustedComment,
    required this.globalSignature,
  });

  factory MinisignSignature.parse(String encoded) {
    final String text = MinisignPublicKey.unwrap(encoded);
    final List<String> lines = text
        .split('\n')
        .map((String line) => line.trimRight())
        .where((String line) => line.trim().isNotEmpty)
        .toList();

    if (lines.length < 4) {
      throw const UpdateFailure(
        'a minisign signature has four lines: untrusted comment, signature, '
        'trusted comment, global signature.',
      );
    }

    final Uint8List raw = _decode(lines[1], 'signature');
    if (raw.length != 2 + _keyIdLength + _signatureLength) {
      throw UpdateFailure(
        'a minisign signature block is 74 bytes; this one is ${raw.length}.',
      );
    }

    final String trustedLine = lines[2].trimLeft();
    if (!trustedLine.startsWith(_trustedPrefix)) {
      throw const UpdateFailure('the third line is not a trusted comment.');
    }

    return MinisignSignature(
      algorithm: _algorithm(raw),
      keyId: Uint8List.sublistView(raw, 2, 2 + _keyIdLength),
      signature: Uint8List.sublistView(raw, 2 + _keyIdLength),
      trustedComment: trustedLine.substring(_trustedPrefix.length).trim(),
      globalSignature: _decode(lines[3], 'global signature'),
    );
  }

  final String algorithm;
  final Uint8List keyId;
  final Uint8List signature;
  final String trustedComment;
  final Uint8List globalSignature;

  bool get isPrehashed => algorithm == 'ED';

  String get keyIdHex => keyId.reversed
      .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();

  /// Os dois primeiros bytes do bloco, recusados quando não são o algoritmo
  /// minisign — o `ascii.decode` padrão lança FormatException para bytes fora
  /// do ASCII, e um cliente não pode morrer com um corpo que o atacante
  /// controla por inteiro.
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

  static Uint8List _decode(String line, String what) {
    try {
      return base64.decode(line.trim());
    } on FormatException {
      throw UpdateFailure('the $what line is not valid base64.');
    }
  }
}
