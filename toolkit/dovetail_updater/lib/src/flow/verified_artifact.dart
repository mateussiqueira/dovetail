import 'dart:typed_data';

final class VerifiedArtifact {
  const VerifiedArtifact.trusted({
    required this.bytes,
    required this.sourceUrl,
    required this.trustedComment,
  });

  final Uint8List bytes;
  final String sourceUrl;
  final String trustedComment;

  int get length => bytes.length;

  String get fileName {
    final Uri? parsed = Uri.tryParse(sourceUrl);
    final Iterable<String> segments =
        parsed?.pathSegments.where((String segment) => segment.isNotEmpty) ??
        const <String>[];
    return segments.isEmpty ? 'update' : segments.last;
  }
}
