import 'dart:io';

import 'package:dovetail_cli/src/config/pubspec_version.dart';
import 'package:path/path.dart' as p;

final class ProjectProbe {
  const ProjectProbe(this.root);

  final String root;

  static const Map<String, String> _osForDirectory = <String, String>{
    'macos': 'darwin',
    'windows': 'windows',
    'linux': 'linux',
  };

  static const List<String> _archesFor = <String>['x86_64', 'aarch64'];

  bool get isFlutterProject =>
      File(p.join(root, PubspecVersion.fileName)).existsSync() &&
      _osForDirectory.keys.any(
        (String directory) => Directory(p.join(root, directory)).existsSync(),
      );

  List<String> get targets => <String>[
    for (final MapEntry<String, String> entry in _osForDirectory.entries)
      if (Directory(p.join(root, entry.key)).existsSync())
        for (final String arch in _archesFor) '${entry.value}-$arch',
  ];

  String? get packageName => PubspecVersion.nameOf(root);

  String get suggestedName {
    final String? name = packageName;
    if (name == null || name.isEmpty) {
      return p.basename(root);
    }
    return name
        .split(RegExp('[_-]'))
        .where((String word) => word.isNotEmpty)
        .map(
          (String word) =>
              word[0].toUpperCase() + word.substring(1).toLowerCase(),
        )
        .join(' ');
  }

  Map<String, String> get declaredIdentifiers {
    final Map<String, String> found = <String, String>{};
    for (final String relative in <String>[
      p.join('macos', 'Runner', 'Configs', 'AppInfo.xcconfig'),
      p.join('linux', 'CMakeLists.txt'),
      p.join('windows', 'runner', 'Runner.rc'),
      p.join('macos', 'Runner.xcodeproj', 'project.pbxproj'),
    ]) {
      final File file = File(p.join(root, relative));
      if (!file.existsSync()) {
        continue;
      }
      for (final RegExpMatch match in _identifierPattern.allMatches(
        file.readAsStringSync(),
      )) {
        final String candidate = match.group(1)!;
        if (_testTargets.any(candidate.endsWith)) {
          continue;
        }
        found.putIfAbsent(relative, () => candidate);
      }
    }
    return found;
  }

  String? get declaredIdentifier {
    final Iterable<String> found = declaredIdentifiers.values;
    for (final String candidate in found) {
      if (isUsableIdentifier(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  static bool isUsableIdentifier(String candidate) =>
      _usablePattern.hasMatch(candidate);

  static String sanitized(String candidate) =>
      candidate.replaceAll(RegExp('[^A-Za-z0-9.-]'), '-');

  static final RegExp _usablePattern = RegExp(
    r'^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$',
  );

  static const List<String> _testTargets = <String>[
    '.RunnerTests',
    '.RunnerUITests',
  ];

  String? get iconPath {
    for (final String candidate in <String>[
      p.join('assets', 'icon.png'),
      p.join('assets', 'images', 'icon.png'),
      p.join('assets', 'icons', 'icon.png'),
    ]) {
      if (File(p.join(root, candidate)).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  static final RegExp _identifierPattern = RegExp(
    r'(?:PRODUCT_BUNDLE_IDENTIFIER\s*=\s*|APPLICATION_ID\s+")'
    r'([A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)+)',
  );
}
