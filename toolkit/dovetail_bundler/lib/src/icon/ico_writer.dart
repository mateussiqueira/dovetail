import 'dart:typed_data';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/icon/icon_source.dart';

abstract final class IcoWriter {
  static const List<int> windowsSizes = <int>[16, 24, 32, 48, 64, 128, 256];

  static const int _headerBytes = 6;
  static const int _entryBytes = 16;
  static const int _maxEdge = 256;

  static Uint8List fromSource(
    IconSource source, {
    List<int> sizes = windowsSizes,
  }) => encode(<int, Uint8List>{
    for (final int edge in sizes) edge: source.pngAt(edge),
  });

  static Uint8List encode(Map<int, Uint8List> pngsByEdge) {
    if (pngsByEdge.isEmpty) {
      throw const BundleFailure(
        'an ico with no image is a file Windows shows as blank.',
      );
    }

    final List<int> edges = pngsByEdge.keys.toList()..sort();
    for (final int edge in edges) {
      if (edge < 1 || edge > _maxEdge) {
        throw BundleFailure(
          'the ico entry of ${edge}px is outside 1..$_maxEdge.',
          remedy:
              'An ico directory stores each edge in one byte, where zero '
              'means 256. There is no way to write a larger one.',
        );
      }
    }

    final int directoryBytes = _headerBytes + _entryBytes * edges.length;
    final BytesBuilder out = BytesBuilder();

    final ByteData header = ByteData(_headerBytes)
      ..setUint16(0, 0, Endian.little)
      ..setUint16(2, 1, Endian.little)
      ..setUint16(4, edges.length, Endian.little);
    out.add(header.buffer.asUint8List());

    int payloadOffset = directoryBytes;
    for (final int edge in edges) {
      final Uint8List png = pngsByEdge[edge]!;
      final ByteData entry = ByteData(_entryBytes)
        ..setUint8(0, edge == _maxEdge ? 0 : edge)
        ..setUint8(1, edge == _maxEdge ? 0 : edge)
        ..setUint8(2, 0)
        ..setUint8(3, 0)
        ..setUint16(4, 1, Endian.little)
        ..setUint16(6, 32, Endian.little)
        ..setUint32(8, png.length, Endian.little)
        ..setUint32(12, payloadOffset, Endian.little);
      out.add(entry.buffer.asUint8List());
      payloadOffset += png.length;
    }

    for (final int edge in edges) {
      out.add(pngsByEdge[edge]!);
    }

    return out.toBytes();
  }
}
