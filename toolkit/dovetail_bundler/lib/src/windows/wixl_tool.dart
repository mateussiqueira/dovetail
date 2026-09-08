import 'dart:io';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';
import 'package:dovetail_process_runner/dovetail_process_runner.dart';

final class WixlTool {
  const WixlTool({required this.runner, this.executable = 'wixl'});

  final ProcessRunner runner;
  final String executable;

  static const Map<TargetArch, String> architectureFor = <TargetArch, String>{
    TargetArch.x86_64: 'x64',
    TargetArch.arm64: 'arm64',
  };

  Future<String> version() async {
    final ProcessOutcome outcome = await runner.run(executable, <String>[
      '--version',
    ]);
    if (!outcome.succeeded) {
      throw BundleFailure(
        '$executable --version failed: ${outcome.firstDiagnostic}',
        remedy:
            'wixl comes with msitools. It writes the MSI database directly, '
            'which is why it works where the WiX toolset cannot: WiX binds '
            'through msi.dll, a Windows system library.',
      );
    }
    return outcome.stdout.trim();
  }

  List<String> argumentsFor({
    required String sourceFile,
    required String outputFile,
    required TargetArch arch,
  }) {
    final String? architecture = architectureFor[arch];
    if (architecture == null) {
      throw BundleFailure(
        'wixl has no name for the ${arch.apple} architecture.',
        remedy: 'It builds for ${architectureFor.values.join(' and ')}.',
      );
    }

    return <String>['-a', architecture, '-o', outputFile, sourceFile];
  }

  Future<void> build({
    required String sourceFile,
    required String outputFile,
    required TargetArch arch,
  }) async {
    if (!File(sourceFile).existsSync()) {
      throw BundleFailure('there is no wxs source at $sourceFile.');
    }

    final String source = File(sourceFile).absolute.path;
    final String output = File(outputFile).absolute.path;

    final ProcessOutcome built = await runner.run(
      executable,
      argumentsFor(sourceFile: source, outputFile: output, arch: arch),
    );

    if (!built.succeeded) {
      throw BundleFailure(
        'wixl exited with ${built.exitCode} and wrote no installer.',
        remedy: built.firstDiagnostic,
      );
    }
    if (!File(output).existsSync()) {
      throw BundleFailure(
        'wixl reported success and $outputFile is not there.',
        remedy:
            'A build that claims to have produced an installer nobody can '
            'find is worse than one that fails.',
      );
    }
  }
}
