import 'dart:convert';
import 'dart:typed_data';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/icon/icon_source.dart';

final class IcnsEntry {
  const IcnsEntry({required this.type, required this.edge});

  final String type;
  final int edge;
}

abstract final class IcnsWriter {
  static const String magic = 'icns';

  static const List<IcnsEntry> appleEntries = <IcnsEntry>[
    IcnsEntry(type: 'icp4', edge: 16),
    IcnsEntry(type: 'icp5', edge: 32),
    IcnsEntry(type: 'ic11', edge: 32),
    IcnsEntry(type: 'ic12', edge: 64),
    IcnsEntry(type: 'ic07', edge: 128),
    IcnsEntry(type: 'ic13', edge: 256),
    IcnsEntry(type: 'ic08', edge: 256),
    IcnsEntry(type: 'ic14', edge: 512),
    IcnsEntry(type: 'ic09', edge: 512),
  ];

  static const int _chunkHeaderBytes = 8;

  static Uint8List fromSource(
    IconSource source, {
    List<IcnsEntry> entries = appleEntries,
  }) => encode(<String, Uint8List>{
    for (final IcnsEntry entry in entries) entry.type: source.pngAt(entry.edge),
  });

  static Uint8List encode(Map<String, Uint8List> pngsByType) {
    if (pngsByType.isEmpty) {
      throw const BundleFailure(
        'an icns with no entry is a bundle macOS shows with a blank icon.',
      );
    }

    for (final String type in pngsByType.keys) {
      if (type.length != 4) {
        throw BundleFailure(
          'the icns type "$type" is not four characters.',
          remedy:
              'Every chunk in an icns is keyed by a four-character type. A '
              'shorter or longer one shifts every chunk after it.',
        );
      }
    }

    final BytesBuilder body = BytesBuilder();
    for (final MapEntry<String, Uint8List> chunk in pngsByType.entries) {
      final ByteData header = ByteData(_chunkHeaderBytes);
      header.buffer.asUint8List().setRange(0, 4, ascii.encode(chunk.key));
      header.setUint32(4, _chunkHeaderBytes + chunk.value.length);
      body
        ..add(header.buffer.asUint8List())
        ..add(chunk.value);
    }

    final Uint8List chunks = body.toBytes();
    final ByteData fileHeader = ByteData(_chunkHeaderBytes);
    fileHeader.buffer.asUint8List().setRange(0, 4, ascii.encode(magic));
    fileHeader.setUint32(4, _chunkHeaderBytes + chunks.length);

    return Uint8List.fromList(<int>[
      ...fileHeader.buffer.asUint8List(),
      ...chunks,
    ]);
  }
}
