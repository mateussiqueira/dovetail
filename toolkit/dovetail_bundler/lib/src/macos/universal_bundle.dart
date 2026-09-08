import 'dart:io';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/macos/mach_o.dart';
import 'package:dovetail_bundler/src/macos/universal_binary.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';
import 'package:path/path.dart' as p;
import 'package:dovetail_process_runner/dovetail_process_runner.dart';

final class UniversalBundle {
  const UniversalBundle({
    required this.runner,
    this.lipo = 'lipo',
    this.ditto = 'ditto',
  });

  final ProcessRunner runner;
  final String lipo;
  final String ditto;

  Future<String> assemble({
    required Map<TargetArch, String> bundles,
    required String output,
  }) async {
    if (bundles.length < 2) {
      throw BundleFailure(
        'a universal bundle needs two builds; ${bundles.length} was given.',
        remedy:
            'One build published under a universal name is an artefact that '
            'will not start on half the machines that download it.',
      );
    }

    for (final MapEntry<TargetArch, String> build in bundles.entries) {
      if (!Directory(build.value).existsSync()) {
        throw BundleFailure(
          'the ${build.key.apple} build is not at ${build.value}.',
          remedy: 'Build each architecture on its own before merging them.',
        );
      }
    }

    final MapEntry<TargetArch, String> template = bundles.entries.first;
    await _copy(template.value, output);

    final List<String> merged = <String>[];
    for (final String relative in _machOFilesIn(output)) {
      final Map<TargetArch, String> slices = <TargetArch, String>{};
      for (final MapEntry<TargetArch, String> build in bundles.entries) {
        final String slice = p.join(build.value, relative);
        if (!File(slice).existsSync()) {
          throw BundleFailure(
            '$relative is in the ${template.key.apple} build and not in the '
            '${build.key.apple} one.',
            remedy:
                'Merging what happens to be in both leaves the difference out '
                'of the universal bundle, and it is missing on exactly one '
                'architecture.',
          );
        }
        slices[build.key] = slice;
      }

      await UniversalBinary(
        runner: runner,
        lipo: lipo,
      ).merge(slices: slices, output: p.join(output, relative));
      merged.add(relative);
    }

    if (merged.isEmpty) {
      throw BundleFailure(
        'no Mach-O file was found in ${template.value}.',
        remedy:
            'A bundle with nothing to merge is a bundle that was not built, '
            'and copying it under a universal name hides that.',
      );
    }

    return output;
  }

  Future<void> _copy(String from, String to) async {
    if (Directory(to).existsSync()) {
      Directory(to).deleteSync(recursive: true);
    }
    final ProcessOutcome copied = await runner.run(ditto, <String>[from, to]);
    if (!copied.succeeded) {
      throw BundleFailure(
        'ditto could not copy $from to $to.',
        remedy: copied.stderr.trim().isEmpty
            ? 'exit code ${copied.exitCode}'
            : copied.stderr.trim(),
      );
    }
  }

  static List<String> _machOFilesIn(String bundlePath) {
    final List<String> found = <String>[];
    for (final FileSystemEntity entity in Directory(
      bundlePath,
    ).listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (!MachO.read(entity.path).isMachO) {
        continue;
      }
      found.add(p.relative(entity.path, from: bundlePath));
    }
    found.sort();
    return found;
  }
}
