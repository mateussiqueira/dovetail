import 'dart:io';

import 'package:dovetail_cli/src/config/config_failure.dart';
import 'package:dovetail_cli/src/config/dovetail_config.dart';
import 'package:path/path.dart' as p;

final class ConfigLocator {
  const ConfigLocator._();

  static const String fileName = 'dovetail.yaml';

  static const int _ceiling = 12;

  static File? findFile({String? from}) {
    Directory here = Directory(from ?? Directory.current.path).absolute;
    for (int step = 0; step < _ceiling; step++) {
      final File candidate = File(p.join(here.path, fileName));
      if (candidate.existsSync()) {
        return candidate;
      }
      final Directory parent = here.parent;
      if (parent.path == here.path) {
        return null;
      }
      here = parent;
    }
    return null;
  }

  static DovetailConfig? load({String? from}) {
    final File? file = findFile(from: from);
    if (file == null) {
      return null;
    }
    return DovetailConfig.parse(file.readAsStringSync(), origin: file.path);
  }

  static DovetailConfig require({String? from}) {
    final DovetailConfig? config = load(from: from);
    if (config == null) {
      throw const ConfigFailure(
        'no dovetail.yaml was found here or in any parent directory.',
        remedy: 'Run: dovetail init',
      );
    }
    return config;
  }

  static String rootFor(File config) => p.dirname(config.path);
}
