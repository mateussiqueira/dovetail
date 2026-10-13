import 'dart:async';
import 'dart:convert';
import 'dart:io';

final class AppLog {
  AppLog({
    required this.path,
    this.maxBytes = 1024 * 1024,
    this.keep = 3,
    this.clock = DateTime.now,
  }) {
    if (keep < 1) {
      throw ArgumentError.value(keep, 'keep', 'must keep at least one file');
    }
  }

  final String path;
  final int maxBytes;
  final int keep;
  final DateTime Function() clock;

  void debug(String message) => write('DEBUG app: $message');

  void info(String message) => write('INFO app: $message');

  void warn(String message) => write('WARN app: $message');

  void error(String message) => write('ERROR app: $message');

  void write(String line) {
    final List<int> bytes = utf8.encode(
      '${clock().toUtc().toIso8601String()} $line\n',
    );
    final File current = File(path);
    final int size = current.existsSync() ? current.lengthSync() : 0;
    if (size == 0) {
      current.parent.createSync(recursive: true);
    } else if (size + bytes.length > maxBytes) {
      _rotate();
    }
    current.writeAsBytesSync(bytes, mode: FileMode.append);
  }

  StreamSubscription<String> attach(Stream<String> lines) =>
      lines.listen(write);

  void _rotate() {
    for (int index = keep - 1; index > 0; index--) {
      final File older = File('$path.$index');
      if (older.existsSync()) {
        older.renameSync('$path.${index + 1}');
      }
    }
    File(path).renameSync('$path.1');
  }
}
