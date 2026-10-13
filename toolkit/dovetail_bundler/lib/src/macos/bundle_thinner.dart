import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/macos/bundle_architectures.dart';
import 'package:dovetail_bundler/src/macos/mach_o.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';
import 'package:dovetail_process_runner/dovetail_process_runner.dart';
import 'package:path/path.dart' as p;

final class BundleThinner {
  const BundleThinner({required this.runner, this.lipo = 'lipo'});

  final ProcessRunner runner;
  final String lipo;

  Future<List<String>> thin({
    required String bundlePath,
    required TargetArch architecture,
  }) async {
    final BundleArchitectureReport report = BundleArchitectures.inspect(
      bundlePath: bundlePath,
      required_: <TargetArch>{architecture},
    );
    if (!report.satisfied) {
      throw BundleFailure(
        'the bundle cannot be thinned to ${architecture.apple}.\n'
        '${report.summary}',
        remedy:
            'Thinning keeps a slice the build already made; it cannot make '
            'one. Build the app for ${architecture.apple} before thinning it.',
      );
    }

    final List<String> thinned = <String>[];
    for (final BundleBinary binary in report.binaries) {
      if (binary.info.kind != MachOKind.fat) {
        continue;
      }
      final String path = p.join(bundlePath, binary.relativePath);
      final ProcessOutcome outcome = await runner.run(lipo, <String>[
        path,
        '-thin',
        architecture.apple,
        '-output',
        path,
      ]);
      if (!outcome.succeeded) {
        throw BundleFailure(
          'lipo could not thin ${binary.relativePath} to '
          '${architecture.apple}.',
          remedy: outcome.stderr.trim(),
        );
      }
      thinned.add(binary.relativePath);
    }
    return thinned;
  }
}
