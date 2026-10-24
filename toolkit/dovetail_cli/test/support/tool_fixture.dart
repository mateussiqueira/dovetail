import 'dart:io';

import 'package:path/path.dart' as p;

String toolFixture(
  Directory root, {
  required String posix,
  required String windows,
}) {
  final String path = p.join(
    root.path,
    Platform.isWindows ? 'fixture.cmd' : 'fixture',
  );
  File(path).writeAsStringSync(
    Platform.isWindows
        ? '@echo off\r\n${windows.replaceAll('\n', '\r\n')}\r\n'
        : '#!/bin/sh\n$posix\n',
  );
  if (!Platform.isWindows) {
    final ProcessResult result = Process.runSync('chmod', <String>[
      '755',
      path,
    ]);
    if (result.exitCode != 0) {
      throw StateError('could not make fixture executable: ${result.stderr}');
    }
  }
  return path;
}
