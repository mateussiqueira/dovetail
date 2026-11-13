import 'dart:io';

import 'package:path/path.dart' as p;

String? findToolExecutable(String name) {
  if (Platform.isWindows && p.dirname(name) != '.') {
    return File(name).existsSync() ? name : null;
  }
  final ProcessResult found = Process.runSync(
    Platform.isWindows ? 'where' : 'which',
    <String>[name],
  );
  if (found.exitCode != 0) {
    return null;
  }
  for (final String line in found.stdout.toString().split('\n')) {
    final String candidate = line.trim();
    if (candidate.isEmpty) {
      continue;
    }
    if (!Platform.isWindows ||
        const <String>{
          '.exe',
          '.com',
          '.bat',
          '.cmd',
        }.contains(p.extension(candidate).toLowerCase())) {
      return candidate;
    }
  }
  return null;
}
