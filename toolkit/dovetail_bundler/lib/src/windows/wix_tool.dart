import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_process_runner/dovetail_process_runner.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';

final class WixTool {
  const WixTool({
    required this.runner,
    this.executable = 'wix',
    this.eulaId = 'wix7',
    this.extensions = const <String>[],
  });

  final ProcessRunner runner;
  final String executable;
  final String eulaId;
  final List<String> extensions;

  Future<String> version() async {
    final ProcessOutcome outcome = await runner.run(executable, <String>[
      '--version',
    ]);
    if (!outcome.succeeded) {
      throw BundleFailure(
        '$executable --version failed: ${outcome.stderr.trim()}',
        remedy:
            'Install it with dotnet tool install --global wix, and note that '
            'it needs the .NET SDK on the runner.',
      );
    }
    return outcome.stdout.trim();
  }

  Future<void> build({
    required String sourceFile,
    required String outputFile,
    required TargetArch arch,
    required List<String> cultures,
    Map<String, String> defines = const <String, String>{},
  }) async {
    final List<String> arguments = <String>[
      'build',
      '-acceptEula',
      eulaId,
      '-arch',
      arch.wix,
      if (cultures.isNotEmpty) ...<String>['-culture', cultures.join(';')],
      for (final String extension in extensions) ...<String>['-ext', extension],
      for (final MapEntry<String, String> define in defines.entries)
        '-d${define.key}=${define.value}',
      '-out',
      outputFile,
      sourceFile,
    ];

    final ProcessOutcome outcome = await runner.run(executable, arguments);
    if (!outcome.succeeded) {
      throw BundleFailure(
        'wix build failed for $sourceFile.',
        remedy: _firstDiagnostic(outcome),
      );
    }
  }

  static String _firstDiagnostic(ProcessOutcome outcome) {
    final String text = outcome.stderr.trim().isEmpty
        ? outcome.stdout
        : outcome.stderr;
    final Iterable<String> lines = text
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty);
    return lines.isEmpty ? 'exit code ${outcome.exitCode}' : lines.first;
  }
}
