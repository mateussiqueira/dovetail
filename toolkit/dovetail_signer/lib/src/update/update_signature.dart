import 'dart:convert';

final class UpdateSignature {
  const UpdateSignature({
    required this.artifactPath,
    required this.signaturePath,
    required this.content,
  });

  final String artifactPath;
  final String signaturePath;
  final String content;

  String get wrappedForManifest => base64.encode(utf8.encode(content));

  String get algorithm {
    final List<int> raw = _block;
    return raw.length < 2 ? '' : String.fromCharCodes(raw.sublist(0, 2));
  }

  bool get isPrehashed => algorithm == 'ED';

  String get keyIdHex {
    final List<int> raw = _block;
    if (raw.length < 10) {
      return '';
    }
    return raw
        .sublist(2, 10)
        .reversed
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
  }

  String get trustedComment {
    final List<String> lines = _lines;
    if (lines.length < 3) {
      return '';
    }
    const String prefix = 'trusted comment:';
    final String line = lines[2].trimLeft();
    return line.startsWith(prefix) ? line.substring(prefix.length).trim() : '';
  }

  List<String> get _lines => content
      .split('\n')
      .where((String line) => line.trim().isNotEmpty)
      .toList();

  List<int> get _block {
    final List<String> lines = _lines;
    if (lines.length < 2) {
      return const <int>[];
    }
    try {
      return base64.decode(lines[1].trim());
    } on FormatException {
      return const <int>[];
    }
  }

  @override
  String toString() => 'UpdateSignature($signaturePath, key $keyIdHex)';
}
