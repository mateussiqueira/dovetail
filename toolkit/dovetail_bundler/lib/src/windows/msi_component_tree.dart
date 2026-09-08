import 'dart:io';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/spec/staged_file.dart';
import 'package:dovetail_bundler/src/windows/msi_component_guid.dart';
import 'package:dovetail_bundler/src/windows/wix_text.dart';
import 'package:path/path.dart' as p;

final class MsiComponent {
  const MsiComponent({
    required this.id,
    required this.guid,
    required this.directoryId,
    required this.relativePath,
    required this.source,
  });

  final String id;
  final String guid;
  final String directoryId;
  final String relativePath;
  final String source;

  String get fileName => p.basename(relativePath);

  String get fileId => WixText.identifier('file.$relativePath', prefix: 'f');

  String get windowsRelativePath => relativePath.replaceAll('/', r'\');
}

final class MsiDirectory {
  const MsiDirectory({
    required this.id,
    required this.name,
    required this.relativePath,
    required this.parentRelativePath,
  });

  final String id;
  final String name;
  final String relativePath;
  final String? parentRelativePath;
}

final class MsiComponentTree {
  MsiComponentTree._(this.components, this.directories);

  factory MsiComponentTree.scan({
    required String appDirectory,
    required String upgradeCode,
    List<StagedFile> extraFiles = const <StagedFile>[],
  }) {
    final Directory root = Directory(appDirectory);
    if (!root.existsSync()) {
      throw BundleFailure(
        'appDirectory "$appDirectory" does not exist.',
        remedy: 'Run flutter build windows before bundling.',
      );
    }

    final Map<String, String> sources = <String, String>{};
    for (final FileSystemEntity entity in root.listSync(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final String relative = p
          .relative(entity.path, from: root.path)
          .replaceAll(r'\', '/');
      sources[relative] = entity.path;
    }
    for (final StagedFile file in extraFiles) {
      sources[file.destination.replaceAll(r'\', '/')] = file.source;
    }

    if (sources.isEmpty) {
      throw BundleFailure(
        'appDirectory "$appDirectory" holds no file.',
        remedy:
            'An MSI with no component installs nothing and uninstalls '
            'nothing.',
      );
    }

    final List<String> ordered = sources.keys.toList()..sort();
    final Map<String, MsiDirectory> directories = <String, MsiDirectory>{};
    final List<MsiComponent> components = <MsiComponent>[];
    final Set<String> usedIds = <String>{};

    for (final String relative in ordered) {
      final String parent = p.url.dirname(relative);
      if (parent != '.') {
        _registerDirectory(directories, parent);
      }

      final String directoryId = parent == '.'
          ? 'INSTALLFOLDER'
          : directories[parent]!.id;
      components.add(
        MsiComponent(
          id: _uniqueId(usedIds, relative),
          guid: MsiComponentGuid.forPath(
            upgradeCode: upgradeCode,
            relativePath: relative,
          ),
          directoryId: directoryId,
          relativePath: relative,
          source: sources[relative]!,
        ),
      );
    }

    final List<MsiDirectory> sortedDirectories = directories.values.toList()
      ..sort(
        (MsiDirectory a, MsiDirectory b) =>
            a.relativePath.compareTo(b.relativePath),
      );

    return MsiComponentTree._(
      List<MsiComponent>.unmodifiable(components),
      List<MsiDirectory>.unmodifiable(sortedDirectories),
    );
  }

  final List<MsiComponent> components;
  final List<MsiDirectory> directories;

  MsiComponent? componentFor(String relativePath) {
    final String needle = relativePath.replaceAll(r'\', '/');
    for (final MsiComponent component in components) {
      if (component.relativePath == needle) {
        return component;
      }
    }
    return null;
  }

  Iterable<MsiDirectory> childrenOf(String? relativePath) => directories.where(
    (MsiDirectory directory) => directory.parentRelativePath == relativePath,
  );

  Iterable<MsiComponent> componentsIn(String directoryId) => components.where(
    (MsiComponent component) => component.directoryId == directoryId,
  );

  static void _registerDirectory(
    Map<String, MsiDirectory> known,
    String relativePath,
  ) {
    if (known.containsKey(relativePath)) {
      return;
    }
    final String parent = p.url.dirname(relativePath);
    final String? parentPath = parent == '.' ? null : parent;
    if (parentPath != null) {
      _registerDirectory(known, parentPath);
    }
    known[relativePath] = MsiDirectory(
      id: WixText.identifier('dir.$relativePath', prefix: 'd'),
      name: p.url.basename(relativePath),
      relativePath: relativePath,
      parentRelativePath: parentPath,
    );
  }

  static String _uniqueId(Set<String> used, String relativePath) {
    final String candidate = WixText.identifier(
      'cmp.$relativePath',
      prefix: 'c',
    );
    if (used.add(candidate)) {
      return candidate;
    }
    int suffix = 2;
    while (!used.add('${candidate}_$suffix')) {
      suffix++;
    }
    return '${candidate}_$suffix';
  }
}
