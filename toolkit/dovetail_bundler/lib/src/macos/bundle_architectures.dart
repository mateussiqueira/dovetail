import 'dart:io';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/macos/mach_o.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';
import 'package:path/path.dart' as p;

final class BundleBinary {
  const BundleBinary({required this.relativePath, required this.info});

  final String relativePath;
  final MachOInfo info;
}

final class BundleArchitectureReport {
  const BundleArchitectureReport({
    required this.bundlePath,
    required this.binaries,
    required this.required_,
  });

  final String bundlePath;
  final List<BundleBinary> binaries;
  final Set<TargetArch> required_;

  Set<TargetArch> get carriedByAll => binaries.isEmpty
      ? const <TargetArch>{}
      : binaries
            .map((BundleBinary binary) => binary.info.architectures)
            .reduce(
              (Set<TargetArch> a, Set<TargetArch> b) => a.intersection(b),
            );

  List<BundleBinary> get missing {
    final List<BundleBinary> short = binaries
        .where(
          (BundleBinary binary) =>
              !binary.info.architectures.containsAll(required_),
        )
        .toList();
    short.sort((BundleBinary a, BundleBinary b) {
      final int depth = _depthOf(a.relativePath) - _depthOf(b.relativePath);
      return depth != 0 ? depth : a.relativePath.compareTo(b.relativePath);
    });
    return List<BundleBinary>.unmodifiable(short);
  }

  static int _depthOf(String relativePath) => p.split(relativePath).length;

  bool get satisfied => binaries.isNotEmpty && missing.isEmpty;

  String get summary {
    if (binaries.isEmpty) {
      return 'no Mach-O file was found in $bundlePath';
    }
    if (satisfied) {
      return '${binaries.length} Mach-O files, all carrying '
          '${required_.map((TargetArch a) => a.apple).join(' + ')}';
    }
    final Iterable<String> lines = missing.take(8).map((BundleBinary binary) {
      final String carried = binary.info.architectures.isEmpty
          ? 'no architecture this bundler knows'
          : binary.info.architectures
                .map((TargetArch a) => a.apple)
                .join(' + ');
      return '  ${binary.relativePath}: $carried';
    });
    final int hidden = missing.length - 8;
    return '${missing.length} of ${binaries.length} Mach-O files do not carry '
        '${required_.map((TargetArch a) => a.apple).join(' + ')}:\n'
        '${lines.join('\n')}'
        '${hidden > 0 ? '\n  and $hidden more' : ''}';
  }
}

abstract final class BundleArchitectures {
  static BundleArchitectureReport inspect({
    required String bundlePath,
    Set<TargetArch> required_ = const <TargetArch>{
      TargetArch.x86_64,
      TargetArch.arm64,
    },
  }) {
    final Directory bundle = Directory(bundlePath);
    if (!bundle.existsSync()) {
      throw BundleFailure('$bundlePath does not exist.');
    }

    final List<BundleBinary> binaries = <BundleBinary>[];
    for (final FileSystemEntity entity in bundle.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }
      final MachOInfo info = MachO.read(entity.path);
      if (!info.isMachO) {
        continue;
      }
      binaries.add(
        BundleBinary(
          relativePath: p.relative(entity.path, from: bundle.path),
          info: info,
        ),
      );
    }

    binaries.sort(
      (BundleBinary a, BundleBinary b) =>
          a.relativePath.compareTo(b.relativePath),
    );

    return BundleArchitectureReport(
      bundlePath: bundlePath,
      binaries: List<BundleBinary>.unmodifiable(binaries),
      required_: required_,
    );
  }

  static void enforce({
    required String bundlePath,
    required Set<TargetArch> required_,
  }) {
    final BundleArchitectureReport report = inspect(
      bundlePath: bundlePath,
      required_: required_,
    );
    if (report.satisfied) {
      return;
    }
    throw BundleFailure(
      'the bundle does not carry every architecture it was asked for.\n'
      '${report.summary}',
      remedy:
          'A dmg published as universal whose binaries are thin installs on '
          'every Mac and starts on half of them. Build each slice and merge '
          'them before wrapping.',
    );
  }
}
