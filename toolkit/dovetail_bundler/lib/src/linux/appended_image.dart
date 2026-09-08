import 'dart:io';
import 'dart:typed_data';

abstract final class AppendedImage {
  static const int chunkBytes = 1 << 20;

  static void write({
    required String runtime,
    required String image,
    required String destination,
  }) {
    final File target = File(destination);
    if (target.existsSync()) {
      target.deleteSync();
    }

    final RandomAccessFile writing = target.openSync(mode: FileMode.write);
    try {
      for (final String part in <String>[runtime, image]) {
        _pour(part, writing);
      }
    } finally {
      writing.closeSync();
    }
  }

  static void _pour(String part, RandomAccessFile into) {
    final RandomAccessFile reading = File(part).openSync();
    try {
      while (true) {
        final Uint8List chunk = reading.readSync(chunkBytes);
        if (chunk.isEmpty) {
          return;
        }
        into.writeFromSync(chunk);
      }
    } finally {
      reading.closeSync();
    }
  }
}
