import 'dart:io';

import 'package:dovetail_bundler/src/bundle_failure.dart';
import 'package:dovetail_process_runner/dovetail_process_runner.dart';
import 'package:dovetail_bundler/src/spec/bundle_spec.dart';
import 'package:dovetail_bundler/src/spec/target_arch.dart';
import 'package:dovetail_bundler/src/windows/nsis_script.dart';
import 'package:dovetail_bundler/src/windows/nsis_utils.dart';
import 'package:path/path.dart' as p;

final class NsisBundler {
  const NsisBundler({
    required this.runner,
    required this.makensis,
    required this.pluginDirectory,
    required this.arch,
    this.unicode = true,
  });

  final ProcessRunner runner;
  final String makensis;
  final String pluginDirectory;
  final TargetArch arch;
  final bool unicode;

  static const String unicodeStubRemedy =
      'makensis ran out of memory writing the Unicode stub. On Apple silicon '
      'it compiles a four line script and aborts on the real generated '
      'installer, and building it from source does not change it, so it is '
      'the toolchain and not this build. Passing '
      'unicode: false compiles here, at a real cost: an ANSI installer reads '
      'paths and strings in the system code page, so a machine whose '
      'installation path is outside it installs to the wrong place. The '
      'alternative is an MSI, which wixl builds on any host.';

  static bool crashedOnUnicodeStub(ProcessOutcome outcome) =>
      '${outcome.stdout}${outcome.stderr}'.contains('bad_alloc');

  Future<String> bundle(BundleSpec spec) async {
    final String installerFileName = spec.installerFileNameFor(arch);
    final Directory appDirectory = Directory(spec.appDirectory);
    if (!appDirectory.existsSync()) {
      throw BundleFailure(
        'The built application is not at ${spec.appDirectory}.',
        remedy: 'Run flutter build windows --release first.',
      );
    }

    final Directory output = Directory(spec.outputDirectory)
      ..createSync(recursive: true);
    final Directory stage = Directory(p.join(output.path, 'nsis'))
      ..createSync(recursive: true);

    File(
      p.join(stage.path, 'dovetail_utils.nsh'),
    ).writeAsStringSync(NsisUtils.source);

    final File script = File(p.join(stage.path, 'installer.nsi'))
      ..writeAsStringSync(NsisScript.render(spec, arch, unicode: unicode));

    final ProcessOutcome outcome = await runner.run(
      makensis,
      <String>[
        '-INPUTCHARSET',
        'UTF8',
        '-OUTPUTCHARSET',
        'UTF8',
        '-V2',
        '-DPLUGINDIR=$pluginDirectory',
        p.basename(script.path),
      ],
      workingDirectory: stage.path,
      environment: <String, String>{
        'DOVETAIL_APP_DIR': appDirectory.absolute.path,
      },
    );

    if (!outcome.succeeded) {
      throw BundleFailure(
        'makensis failed with exit code ${outcome.exitCode}.',
        remedy: crashedOnUnicodeStub(outcome)
            ? unicodeStubRemedy
            : outcome.stderr.trim().isEmpty
            ? outcome.stdout.trim()
            : outcome.stderr.trim(),
      );
    }

    final String produced = p.join(stage.path, installerFileName);
    if (!File(produced).existsSync()) {
      throw BundleFailure(
        'makensis reported success but $installerFileName is not there.',
        remedy: 'Check OutFile in the generated installer.nsi.',
      );
    }

    final String destination = p.join(output.path, installerFileName);
    File(produced).renameSync(destination);
    return destination;
  }
}
