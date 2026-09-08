import 'dart:io';

import 'package:dovetail_cli/src/config/config_failure.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

final class PubspecVersion {
  const PubspecVersion._();

  static const String fileName = 'pubspec.yaml';

  static String read(String projectRoot) {
    final File pubspec = File(p.join(projectRoot, fileName));
    if (!pubspec.existsSync()) {
      throw ConfigFailure(
        'no $fileName beside the config.',
        remedy:
            'The release version is read from the project, never duplicated '
            'into dovetail.yaml, so the two can never disagree.',
        origin: projectRoot,
      );
    }

    final Object? document = loadYaml(pubspec.readAsStringSync());
    final Object? version = document is Map ? document['version'] : null;
    if (version is! String || version.trim().isEmpty) {
      throw ConfigFailure(
        '$fileName declares no version.',
        remedy: 'Add "version: 1.0.0" to it, or pass --version explicitly.',
        origin: pubspec.path,
      );
    }

    return version.split('+').first.trim();
  }

  static String? nameOf(String projectRoot) {
    final File pubspec = File(p.join(projectRoot, fileName));
    if (!pubspec.existsSync()) {
      return null;
    }
    final Object? document = loadYaml(pubspec.readAsStringSync());
    final Object? name = document is Map ? document['name'] : null;
    return name is String && name.isNotEmpty ? name : null;
  }
}
