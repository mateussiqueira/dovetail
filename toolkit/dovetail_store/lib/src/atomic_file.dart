import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

@Native<Int32 Function(Pointer<Uint8>, Int32)>(symbol: 'open', isLeaf: true)
external int _open(Pointer<Uint8> path, int flags);

@Native<Int32 Function(Int32)>(symbol: 'fsync')
external int _fsync(int descriptor);

@Native<Int32 Function(Int32)>(symbol: 'close')
external int _close(int descriptor);

final class AtomicFile {
  const AtomicFile(this.path, {this.syncDirectory = AtomicFile.fsyncDirectory});

  final String path;
  final void Function(String directory) syncDirectory;

  String get temporaryPath => '$path.tmp';

  Uint8List? read() {
    try {
      return File(path).readAsBytesSync();
    } on PathNotFoundException {
      return null;
    }
  }

  void write(Iterable<List<int>> chunks) {
    final File temporary = File(temporaryPath);
    final RandomAccessFile sink = temporary.openSync(mode: FileMode.writeOnly);
    try {
      for (final List<int> chunk in chunks) {
        sink.writeFromSync(chunk);
      }
      sink.flushSync();
    } on Object {
      sink.closeSync();
      temporary.deleteSync();
      rethrow;
    }
    sink.closeSync();
    temporary.renameSync(path);
    syncDirectory(temporary.parent.path);
  }

  static void fsyncDirectory(String directory) {
    if (Platform.isWindows) {
      return;
    }
    final Uint8List name = Uint8List.fromList(<int>[
      ...utf8.encode(directory),
      0,
    ]);
    final int descriptor = _open(name.address, 0);
    if (descriptor < 0) {
      throw FileSystemException('cannot open the directory to sync', directory);
    }
    final int synced = _fsync(descriptor);
    _close(descriptor);
    if (synced != 0) {
      throw FileSystemException('cannot sync the directory', directory);
    }
  }
}
