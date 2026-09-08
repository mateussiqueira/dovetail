import 'dart:io';

import 'package:dovetail_platform_channel/src/window/window_placement.dart';
import 'package:path/path.dart' as p;

abstract interface class WindowStateStore {
  WindowPlacement load();
  void save(WindowPlacement placement);
  void clear();
}

final class FileWindowStateStore implements WindowStateStore {
  const FileWindowStateStore({
    required this.directory,
    this.fileName = 'window_state.json',
  });

  final String directory;
  final String fileName;

  String get path => p.join(directory, fileName);

  @override
  WindowPlacement load() {
    final File file = File(path);
    if (!file.existsSync()) {
      return const WindowPlacement.unknown();
    }
    try {
      return WindowPlacement.decode(file.readAsStringSync());
    } on Object {
      return const WindowPlacement.unknown();
    }
  }

  @override
  void save(WindowPlacement placement) {
    if (placement.isEmpty) {
      return;
    }
    Directory(directory).createSync(recursive: true);
    File(path).writeAsStringSync(placement.encode());
  }

  @override
  void clear() {
    final File file = File(path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}
