import 'dart:io';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_process_runner/dovetail_process_runner.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';

final class UniversalBinary {
  const UniversalBinary({required this.runner, this.lipo = 'lipo'});

  final ProcessRunner runner;
  final String lipo;

  Future<Set<TargetArch>> architecturesOf(String path) async {
    if (!File(path).existsSync()) {
      throw BundleFailure(
        '$path does not exist, so it carries no architecture.',
      );
    }

    final ProcessOutcome outcome = await runner.run(lipo, <String>[
      '-archs',
      path,
    ]);
    if (!outcome.succeeded) {
      throw BundleFailure(
        'lipo could not read the architectures of $path.',
        remedy: outcome.stderr.trim(),
      );
    }

    return outcome.stdout
        .trim()
        .split(RegExp(r'\s+'))
        .where((String name) => name.isNotEmpty)
        .map(TargetArch.parse)
        .toSet();
  }

  Future<String> merge({
    required Map<TargetArch, String> slices,
    required String output,
  }) async {
    if (slices.length < 2) {
      throw BundleFailure(
        'a universal binary needs at least two slices; '
        '${slices.length} was given.',
        remedy:
            'Shipping one slice under a universal name means half the '
            'machines download an artefact that will not start.',
      );
    }

    for (final MapEntry<TargetArch, String> slice in slices.entries) {
      if (!File(slice.value).existsSync()) {
        throw BundleFailure(
          'the ${slice.key.apple} slice is missing: ${slice.value}',
          remedy: 'Build every slice before merging them.',
        );
      }
      final Set<TargetArch> found = await architecturesOf(slice.value);
      if (!found.contains(slice.key)) {
        throw BundleFailure(
          '${slice.value} was given as the ${slice.key.apple} slice but '
          'carries ${found.map((TargetArch a) => a.apple).join(', ')}.',
          remedy:
              'A merge that trusts the label produces a binary that is fat '
              'and still wrong on one of the two architectures.',
        );
      }
    }

    Directory(File(output).parent.path).createSync(recursive: true);
    final ProcessOutcome merged = await runner.run(lipo, <String>[
      '-create',
      ...slices.values,
      '-output',
      output,
    ]);
    if (!merged.succeeded) {
      throw BundleFailure(
        'lipo could not merge the slices into $output.',
        remedy: merged.stderr.trim(),
      );
    }

    final Set<TargetArch> carried = await architecturesOf(output);
    if (!carried.containsAll(slices.keys)) {
      throw BundleFailure(
        '$output carries ${carried.map((TargetArch a) => a.apple).join(', ')} '
        'but was asked for '
        '${slices.keys.map((TargetArch a) => a.apple).join(', ')}.',
        remedy: 'Treat a merge that lost a slice as a failure, not a pass.',
      );
    }
    return output;
  }
}
