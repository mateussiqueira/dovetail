import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dovetail_bundler/src/bundle_failure.dart';

abstract final class MsiComponentGuid {
  static String forPath({
    required String upgradeCode,
    required String relativePath,
  }) {
    final Uint8List namespace = _namespaceOf(upgradeCode);
    final String name = relativePath
        .replaceAll(r'\', '/')
        .toLowerCase()
        .replaceAll(RegExp('^/+'), '');

    final Digest digest = sha1.convert(<int>[...namespace, ...name.codeUnits]);
    final Uint8List bytes = Uint8List.fromList(digest.bytes.sublist(0, 16));
    bytes[6] = (bytes[6] & 0x0F) | 0x50;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    return format(bytes);
  }

  static String format(Uint8List bytes) {
    String slice(int from, int to) => bytes
        .sublist(from, to)
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();

    return '${slice(0, 4)}-${slice(4, 6)}-${slice(6, 8)}-'
        '${slice(8, 10)}-${slice(10, 16)}';
  }

  static Uint8List _namespaceOf(String upgradeCode) {
    final String hex = upgradeCode
        .trim()
        .replaceAll('{', '')
        .replaceAll('}', '')
        .replaceAll('-', '');
    if (hex.length != 32 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
      throw BundleFailure(
        'upgradeCode "$upgradeCode" is not a GUID.',
        remedy:
            'Write it as 12345678-1234-1234-1234-123456789ABC. It is the '
            'identity every future upgrade of this product is matched '
            'against, so it is generated once and never changed.',
      );
    }

    final Uint8List bytes = Uint8List(16);
    for (int index = 0; index < 16; index++) {
      bytes[index] = int.parse(
        hex.substring(index * 2, index * 2 + 2),
        radix: 16,
      );
    }
    return bytes;
  }
}
